"""Admin suspension actually locks a reader out of the API.

The `client` fixture overrides get_current_user, so it can't exercise this —
these call the real dependency with JWT verification monkeypatched away, against
a real profile row, to prove the DB check itself gates access.
"""

import types
import uuid
from datetime import UTC, datetime

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

import app.core.security as sec
from app.models import Profile


def _fake_jwt(monkeypatch, sub: str) -> None:
    monkeypatch.setattr(
        sec,
        "_get_jwks_client",
        lambda: types.SimpleNamespace(
            get_signing_key_from_jwt=lambda _t: types.SimpleNamespace(key="k")
        ),
    )
    monkeypatch.setattr(
        sec.jwt, "decode", lambda *a, **k: {"sub": sub, "email": "reader@example.com"}
    )


_CREDS = HTTPAuthorizationCredentials(scheme="Bearer", credentials="tok")


async def test_suspended_reader_is_rejected(db_sessionmaker, monkeypatch):
    uid = uuid.uuid4()
    async with db_sessionmaker() as db:
        db.add(Profile(id=uid, email="reader@example.com", suspended_at=datetime.now(UTC)))
        await db.commit()
    _fake_jwt(monkeypatch, str(uid))

    async with db_sessionmaker() as db:
        with pytest.raises(HTTPException) as ei:
            await sec.get_current_user(_CREDS, db)
    assert ei.value.status_code == 403
    assert ei.value.detail["code"] == "account_suspended"


async def test_active_reader_passes(db_sessionmaker, monkeypatch):
    uid = uuid.uuid4()
    async with db_sessionmaker() as db:
        db.add(Profile(id=uid, email="reader@example.com"))  # suspended_at NULL
        await db.commit()
    _fake_jwt(monkeypatch, str(uid))

    async with db_sessionmaker() as db:
        user = await sec.get_current_user(_CREDS, db)
    assert user["id"] == str(uid)


async def test_reader_without_a_profile_row_is_not_blocked(db_sessionmaker, monkeypatch):
    """A brand-new user mid-bootstrap has no profile row yet — they must not be
    treated as suspended, or first sign-in would break."""
    uid = uuid.uuid4()
    _fake_jwt(monkeypatch, str(uid))

    async with db_sessionmaker() as db:
        user = await sec.get_current_user(_CREDS, db)
    assert user["id"] == str(uid)
