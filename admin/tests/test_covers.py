"""Editing a book's covers from the console.

Three things are worth pinning. What gets *stored* is never what arrived: a
cover is decoded, shrunk and re-encoded before it reaches the bucket, which is
also what strips a phone photo's EXIF (GPS included). A pasted link is fetched
only if it is one we are willing to fetch, and one that is already ours is
taken as it is — which is how an operator undoes a change with the URL the
audit log kept. And every change is audited with the URL it replaced.

No network and no database: storage, fetching, the session and the audit are
patched out; Pillow is real.
"""

import asyncio
import base64
import io
import sys
import typing
import uuid
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
# `console.assets` imports the API package directly; put it on the path the way
# `console/models_ref.py` does, before anything is imported from it.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "api"))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jinja2 import StrictUndefined
from PIL import Image

from console import assets, deps, security
from console.routers import catalog
from console.templating import templates

BASE = "https://example.supabase.co"
OURS = f"{BASE}/storage/v1/object/public/covers/covers/old.jpg"
OPENLIBRARY = "https://covers.openlibrary.org/b/id/12345-L.jpg"


def _image(width: int, height: int, fmt: str = "PNG", **save) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", (width, height), (126, 42, 51)).save(out, fmt, **save)
    return out.getvalue()


@pytest.fixture
def storage(monkeypatch):
    """Uploads switched on, with every PUT captured instead of sent."""
    puts: list[dict] = []

    async def put(path, body, content_type, *, upsert=False):  # noqa: ANN001
        puts.append({"path": path, "body": body, "type": content_type, "upsert": upsert})

    monkeypatch.setattr(assets, "_put", put)
    monkeypatch.setattr(assets, "_base", lambda: BASE)
    monkeypatch.setattr(assets, "_service_key", lambda: "service-role")
    return puts


def run(coro):  # noqa: ANN001, ANN201
    return asyncio.run(coro)


# --- what is stored ---------------------------------------------------------


def test_a_cover_is_shrunk_and_stored_as_a_jpeg_in_the_covers_folder(storage):
    url = run(assets.store_cover(_image(1200, 1800)))
    (put,) = storage
    assert put["path"].startswith("covers/") and put["path"].endswith(".jpg")
    assert put["type"] == "image/jpeg"
    assert url == f"{BASE}/storage/v1/object/public/covers/{put['path']}"
    with Image.open(io.BytesIO(put["body"])) as stored:
        assert stored.format == "JPEG"
        assert max(stored.size) == 800, "the longest edge is capped"


def test_the_same_picture_is_the_same_object(storage):
    # Content-addressed, so a double-submit writes one object, not two.
    body = _image(600, 900)
    assert run(assets.store_cover(body)) == run(assets.store_cover(body))
    assert storage[0]["path"] == storage[1]["path"]
    assert storage[0]["upsert"] is True


def test_a_phone_photo_loses_its_metadata(storage):
    exif = Image.Exif()
    exif[0x8825] = {2: (9, 58, 0)}  # GPSInfo → a latitude
    exif[0x010F] = "PhoneMaker"  # Make
    run(assets.store_cover(_image(900, 1350, "JPEG", exif=exif.tobytes())))
    with Image.open(io.BytesIO(storage[0]["body"])) as stored:
        assert not dict(stored.getexif()), "EXIF must not survive into the public bucket"


@pytest.mark.parametrize(
    ("body", "why"),
    [
        (_image(60, 90), "a thumbnail is not cover art"),
        (_image(1200, 200), "a banner is not book-shaped"),
        (b"<html>not an image</html>", "not an image at all"),
        (b"", "empty"),
    ],
    ids=["thumbnail", "banner", "html", "empty"],
)
def test_what_is_not_a_cover_is_refused_and_nothing_is_stored(storage, body, why):
    with pytest.raises(assets.CoverError):
        run(assets.store_cover(body))
    assert storage == [], why


def test_with_uploads_off_a_file_is_refused_with_the_reason(monkeypatch):
    monkeypatch.setattr(assets, "_service_key", lambda: None)
    monkeypatch.setattr(assets, "_base", lambda: BASE)
    with pytest.raises(assets.CoverError, match="SUPABASE_SERVICE_ROLE_KEY"):
        run(assets.store_cover(_image(600, 900)))


# --- a pasted link ----------------------------------------------------------


def _no_fetch(monkeypatch):
    async def boom(client, url):  # noqa: ANN001
        raise AssertionError(f"fetched {url}")

    monkeypatch.setattr(assets.cover_ingest, "_fetch", boom)


def test_a_link_that_is_already_ours_is_taken_as_it_is(monkeypatch):
    # This is the undo path: the audit log keeps the old URL, and pasting it
    # back must work even with uploads switched off.
    _no_fetch(monkeypatch)
    monkeypatch.setattr(assets, "_service_key", lambda: None)
    assert run(assets.cover_from_url(f"  {OPENLIBRARY} ")) == OPENLIBRARY
    monkeypatch.setattr(assets, "cover_url_is_ours", lambda url: url == OURS)
    assert run(assets.cover_from_url(OURS)) == OURS


@pytest.mark.parametrize(
    "url",
    [
        "http://shop.example.com/cover.jpg",  # not https
        "https://10.0.0.5/cover.jpg",  # an IP literal
        "https://metadata.internal/cover.jpg",  # a private-network name
        "https://user:pw@shop.example.com/c.jpg",  # credentials
        "file:///etc/passwd",
    ],
)
def test_a_link_we_will_not_fetch_is_refused_before_any_request(storage, monkeypatch, url):
    _no_fetch(monkeypatch)
    with pytest.raises(assets.CoverError, match="https://"):
        run(assets.cover_from_url(url))


def test_an_outside_link_is_copied_not_linked_to(storage, monkeypatch):
    body = _image(500, 750, "JPEG")
    seen = {}

    async def fetch(client, url):  # noqa: ANN001
        seen["ua"] = client.headers.get("user-agent", "")
        return assets.cover_ingest.cover_storage.Fetched(body=body, content_type="image/jpeg")

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)
    url = run(assets.cover_from_url("https://shop.example.com/cover.jpg"))
    assert url.startswith(f"{BASE}/storage/v1/object/public/covers/covers/")
    assert len(storage) == 1
    # Wikimedia 403s python-httpx's default; the console says who it is.
    assert seen["ua"].startswith("Kitabi/")


@pytest.mark.parametrize(
    ("fetched", "message"),
    [({"gone": True}, "isn't there"), ({}, "wouldn't hand the image over")],
)
def test_a_link_that_yields_no_image_says_why(storage, monkeypatch, fetched, message):
    async def fetch(client, url):  # noqa: ANN001
        return assets.cover_ingest.cover_storage.Fetched(**fetched)

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)
    with pytest.raises(assets.CoverError, match=message):
        run(assets.cover_from_url("https://shop.example.com/cover.jpg"))
    assert storage == []


# --- the routes -------------------------------------------------------------

WORK_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")
OTHER_WORK = uuid.UUID("44444444-4444-4444-4444-444444444444")
ED_ID = uuid.UUID("55555555-5555-5555-5555-555555555555")
STRAY_ED = uuid.UUID("66666666-6666-6666-6666-666666666666")
ADMIN = SimpleNamespace(id=uuid.uuid4(), role="editor", email="op@kitabi.in")


class _DB:
    def __init__(self):
        self.work = SimpleNamespace(id=WORK_ID, title="Chemmeen", deleted_at=None)
        self.edition = SimpleNamespace(
            id=ED_ID,
            work_id=WORK_ID,
            deleted_at=None,
            cover_url=OURS,
            back_cover_url=None,
            isbn="9788126403455",
            publisher=None,
            page_count=240,
            updated_at=None,
        )
        self.stray = SimpleNamespace(
            **{**vars(self.edition), "id": STRAY_ED, "work_id": OTHER_WORK}
        )
        self.commits = 0

    async def get(self, model, row_id):  # noqa: ANN001
        return {WORK_ID: self.work, ED_ID: self.edition, STRAY_ED: self.stray}.get(row_id)

    async def commit(self):
        self.commits += 1


@pytest.fixture
def app(monkeypatch):
    db = _DB()
    audits: list[dict] = []
    calls: dict = {}

    async def audit(session, action, **kw):  # noqa: ANN001
        audits.append({"action": action, **kw})

    async def from_url(url):  # noqa: ANN001
        calls["url"] = url
        if "bad" in url:
            raise assets.CoverError("Couldn't get an image from that link.")
        return f"{BASE}/storage/v1/object/public/covers/covers/new.jpg"

    async def store(body):  # noqa: ANN001
        calls["file"] = body
        return f"{BASE}/storage/v1/object/public/covers/covers/uploaded.jpg"

    monkeypatch.setattr(security, "audit", audit)
    monkeypatch.setattr(assets, "cover_from_url", from_url)
    monkeypatch.setattr(assets, "store_cover", store)

    a = FastAPI()
    a.include_router(catalog.router)
    require_editor = typing.get_args(deps.RequireEditor)[1].dependency
    a.dependency_overrides[require_editor] = lambda: ADMIN
    a.dependency_overrides[deps.get_db] = lambda: db
    c = TestClient(a)
    c.db, c.audits, c.calls = db, audits, calls
    return c


def _flash(res) -> str:  # noqa: ANN001
    raw = res.cookies.get("admin_flash")
    return base64.urlsafe_b64decode(raw.encode()).decode() if raw else ""


def _post(client, path, data=None, files=None):  # noqa: ANN001, ANN202
    return client.post(
        f"/catalog/works/{WORK_ID}/editions/{ED_ID}/cover{path}",
        data=data or {},
        files=files,
        follow_redirects=False,
    )


def test_a_pasted_link_replaces_the_front_and_the_old_one_is_kept_in_the_audit(app):
    res = _post(app, "", {"side": "front", "url": "https://shop.example.com/c.jpg"})
    assert res.status_code == 303
    assert res.headers["location"] == f"/catalog/works/{WORK_ID}#covers"
    assert app.db.edition.cover_url.endswith("/covers/new.jpg")
    assert app.db.edition.updated_at is not None
    (line,) = app.audits
    assert line["action"] == "edition.cover.front.set"
    assert line["target_type"] == "work" and line["target_id"] == str(WORK_ID)
    assert f"was {OURS}" in line["summary"], "the undo path is the URL in this line"
    assert _flash(res).startswith("ok|")


def test_a_chosen_file_wins_over_a_link_left_in_the_box(app):
    files = {"file": ("back.png", _image(600, 900), "image/png")}
    _post(app, "", {"side": "back", "url": "https://shop.example.com/stale.jpg"}, files)
    assert "file" in app.calls and "url" not in app.calls
    assert app.db.edition.back_cover_url.endswith("/covers/uploaded.jpg")
    assert app.db.edition.cover_url == OURS, "the other side is untouched"
    assert app.audits[0]["action"] == "edition.cover.back.set"


def test_a_failed_cover_changes_nothing_and_says_why(app):
    res = _post(app, "", {"side": "front", "url": "https://bad.example.com/x.jpg"})
    assert app.db.edition.cover_url == OURS
    assert app.db.commits == 0 and app.audits == []
    assert _flash(res).startswith("err|Front cover not changed — Couldn't get an image")


def test_remove_clears_one_side_and_audits_what_was_there(app):
    _post(app, "/remove", {"side": "front"})
    assert app.db.edition.cover_url is None
    assert app.audits[0]["action"] == "edition.cover.front.remove"
    assert f"was {OURS}" in app.audits[0]["summary"]


def test_swap_turns_a_back_to_front_pair_round(app):
    app.db.edition.back_cover_url = "B"
    _post(app, "/swap")
    assert (app.db.edition.cover_url, app.db.edition.back_cover_url) == ("B", OURS)
    assert app.audits[0]["action"] == "edition.cover.swap"


def test_an_edition_of_another_book_is_refused(app):
    res = app.post(
        f"/catalog/works/{WORK_ID}/editions/{STRAY_ED}/cover",
        data={"side": "front", "url": "https://shop.example.com/c.jpg"},
        follow_redirects=False,
    )
    assert app.db.stray.cover_url == OURS
    assert app.audits == [] and app.db.commits == 0
    assert _flash(res).startswith("err|")


def test_an_unknown_side_is_refused(app):
    res = _post(app, "", {"side": "spine", "url": "https://shop.example.com/c.jpg"})
    assert app.audits == [] and "url" not in app.calls
    assert _flash(res) == "err|Unknown cover side."


# --- the book page ----------------------------------------------------------


def test_the_book_page_offers_both_sides_of_every_edition():
    env = templates.env
    old = env.undefined
    env.undefined = StrictUndefined
    try:
        bare = SimpleNamespace(
            id=STRAY_ED,
            isbn=None,
            publisher=None,
            language=None,
            page_count=None,
            format=None,
            cover_url=None,
            back_cover_url=None,
        )
        front_only = SimpleNamespace(**{**vars(bare), "id": ED_ID, "cover_url": OURS})
        work = SimpleNamespace(
            id=WORK_ID,
            title="Chemmeen",
            title_translit="chemmeen",
            slug="chemmeen",
            first_publish_year=1956,
            authors=[],
            translators=[],
            language="Malayalam",
            form="Novel",
            genres=[],
            external_source=None,
            created_at=None,
            description=None,
            series=None,
            series_number=None,
            editions=[front_only, bare],
        )
        html = env.get_template("book_detail.html").render(
            request=SimpleNamespace(url=SimpleNamespace(path="/", query="")),
            admin=ADMIN,
            badges={"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0},
            active="catalog",
            flash=None,
            w=work,
            shelved=0,
            ratings=0,
            reviews=0,
            adder=None,
            amazon_links={},
            series_q="",
            series_matches=[],
            uploads_on=True,
            uploads_why="",
        )
    finally:
        env.undefined = old

    assert 'id="covers"' in html
    action = f'action="/catalog/works/{WORK_ID}/editions/{ED_ID}/cover"'
    assert html.count(action) == 2, "a form for the front and one for the back"
    assert 'enctype="multipart/form-data"' in html, "or the file never reaches the server"
    assert html.count('name="side" value="front"') >= 2
    assert html.count('name="side" value="back"') >= 2
    # Remove only where there is something to remove; swap only where there
    # is anything at all.
    assert html.count("/cover/remove") == 1
    assert html.count("/cover/swap") == 1
    assert f'href="#covers-{ED_ID}"' in html, "the editions table jumps to the cover row"
