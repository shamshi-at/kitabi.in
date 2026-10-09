"""Admin users: resending an invite that hasn't been accepted.

Owner request, 9 Oct 2026. The setup link lasts 48 hours and goes by email, so
it can expire or land in spam; until now the only way round that was to revoke
the admin and create them again under the same email — which the unique email
refuses.

What is pinned:

- **who counts as pending** — active, never signed in, and no
  `admin.invite_accepted` in the trail;
- **the resend is refused once accepted** — a setup link *sets the password*, so
  on an accepted account it would let one admin take over another's;
- a resend mints a fresh token (which voids the old one), emails it, and is
  audited under its own verb.

No database and no network: the db, mail, token store and audit are faked.
"""

import asyncio
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "api"))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jinja2 import StrictUndefined

from console import deps, mail, queries, security
from console.routers import admins
from console.templating import templates

ME = uuid.UUID("99999999-9999-9999-9999-999999999999")
PENDING = uuid.UUID("11111111-1111-1111-1111-111111111111")
ACCEPTED = uuid.UUID("22222222-2222-2222-2222-222222222222")
SIGNED_IN = uuid.UUID("33333333-3333-3333-3333-333333333333")
REVOKED = uuid.UUID("44444444-4444-4444-4444-444444444444")


def _admin(id_, email, *, active=True, signed_in=False, role="moderator"):
    return SimpleNamespace(
        id=id_,
        email=email,
        role=role,
        is_active=active,
        last_sign_in_at=datetime(2026, 10, 1, tzinfo=UTC) if signed_in else None,
        totp_enrolled_at=datetime(2026, 10, 1, tzinfo=UTC) if signed_in else None,
    )


def _rows():
    return [
        _admin(ME, "op@kitabi.in", signed_in=True, role="super_admin"),
        _admin(PENDING, "new@example.com"),
        # Set a password from the link but hasn't signed in yet.
        _admin(ACCEPTED, "set@example.com"),
        _admin(SIGNED_IN, "old@example.com", signed_in=True),
        _admin(REVOKED, "gone@example.com", active=False),
    ]


class _DB:
    """Answers two questions: the admin list (and `get` by id), and which of a
    set of ids have an `admin.invite_accepted` row in the trail."""

    def __init__(self):
        self.rows = _rows()
        self.accepted = {ACCEPTED}
        self.asked = []

    async def execute(self, stmt):  # noqa: ANN001, ANN202
        sql = str(stmt)
        self.asked.append(sql)
        if "admin_audit_log" in sql:
            values = self.accepted
        else:
            values = self.rows
        return SimpleNamespace(
            scalars=lambda: SimpleNamespace(all=lambda: list(values)),
        )

    async def get(self, _model, id_):  # noqa: ANN001, ANN202
        return next((a for a in self.rows if a.id == id_), None)


@pytest.fixture
def client(monkeypatch):
    state = {"audits": [], "tokens": [], "sent": [], "mail": True}
    db = _DB()

    async def audit(db_, action, **kw):  # noqa: ANN001
        state["audits"].append({"action": action, **kw})

    async def badges(db_):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    async def token(db_, admin_id, purpose, plaintext, ttl_minutes):  # noqa: ANN001
        state["tokens"].append((admin_id, purpose, plaintext, ttl_minutes))

    monkeypatch.setattr(security, "audit", audit)
    monkeypatch.setattr(security, "create_auth_token", token)
    monkeypatch.setattr(queries, "nav_badges", badges)
    monkeypatch.setattr(mail, "send", lambda to, subject, text, html=None: state["sent"].append(to))
    monkeypatch.setattr(mail, "is_configured", lambda: state["mail"])
    monkeypatch.setattr(mail, "base_url", lambda: "https://admin.kitabi.in")
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(admins.router)
    app.dependency_overrides[deps.current_admin] = lambda: _admin(
        ME, "op@kitabi.in", signed_in=True, role="super_admin"
    )
    app.dependency_overrides[deps.get_db] = lambda: db
    c = TestClient(app)
    c.state = state
    c.db = db
    return c


def test_only_an_unaccepted_invite_counts_as_pending():
    db = _DB()
    assert asyncio.run(admins._invite_pending(db, db.rows)) == {PENDING}


def test_nobody_to_check_asks_the_trail_nothing():
    db = _DB()
    signed_in = [a for a in db.rows if a.last_sign_in_at is not None]
    assert asyncio.run(admins._invite_pending(db, signed_in)) == set()
    assert db.asked == []


def test_the_list_offers_a_resend_only_to_the_pending_admin(client):
    html = client.get("/admins").text
    assert html.count("Invite pending") == 1
    assert f'action="/admins/{PENDING}/resend-invite"' in html
    for other in (ME, ACCEPTED, SIGNED_IN, REVOKED):
        assert f'action="/admins/{other}/resend-invite"' not in html


def test_a_resend_mints_a_new_link_emails_it_and_is_audited(client):
    r = client.post(f"/admins/{PENDING}/resend-invite", follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/admins"
    [(admin_id, purpose, _tok, ttl)] = client.state["tokens"]
    assert (admin_id, purpose, ttl) == (PENDING, "invite", 48 * 60)
    assert client.state["sent"] == ["new@example.com"]
    [entry] = client.state["audits"]
    assert entry["action"] == "admin.invite_resend"
    assert entry["admin_id"] == ME and entry["target_id"] == str(PENDING)


@pytest.mark.parametrize("target", [ACCEPTED, SIGNED_IN, REVOKED, ME])
def test_a_resend_is_refused_once_the_invite_is_accepted(client, target):
    """A setup link sets the password — on an accepted account it would be a
    way for one admin to take over another's."""
    r = client.post(f"/admins/{target}/resend-invite", follow_redirects=False)
    assert r.status_code == 303
    assert client.state["tokens"] == []
    assert client.state["sent"] == []
    assert client.state["audits"] == []


def test_without_mail_the_new_link_is_shown_once(client):
    client.state["mail"] = False
    r = client.post(f"/admins/{PENDING}/resend-invite", follow_redirects=False)
    [(_, _, tok, _)] = client.state["tokens"]
    assert f"/invite/{tok}" in r.headers["set-cookie"]
