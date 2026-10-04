"""Image uploads — book covers, publisher logos, author portraits and campaign
artwork.

Writes to the **same public `covers` bucket the app already uses**
(`app/lib/features/catalog/catalog_image_upload.dart`), under the same folder
convention: `publishers/…`, `authors/…`, plus `campaigns/…` for promo artwork.
The Storage policy is bucket-scoped (`bucket_id = 'covers'`), so a new prefix
inside it needs no extra setup.

One storage system, not two. An earlier pass here added a second Cloudflare R2
bucket and boto3 before checking — the app has uploaded author portraits and
publisher logos to Supabase Storage since Phase 2, and a second home for the
same kind of asset is a second credential and a second thing to reason about
for no gain (CLAUDE.md rule 8). R2 stays what it is: the backup target.

Plain httpx against the Storage REST API rather than the supabase client — one
POST, and httpx is already a dependency of both services.

**Dormant until configured**, like `console/mail.py`: without a service-role key
`configured()` is False, the console hides the upload control and says to paste
a URL instead. Nothing breaks and nothing 500s.
"""

import asyncio
import hashlib
import os
import uuid

import httpx
from app.core.config import get_settings
from app.services import cover_ingest

# The bucket the app writes to. Public-read, which is what makes the stored URL
# usable directly as `cover_url` / `logo_url` / a campaign image.
BUCKET = "covers"

# Only what a browser will render and we're willing to serve back.
ALLOWED = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/svg+xml": ".svg",
}
MAX_BYTES = 2 * 1024 * 1024  # a logo or a card image; anything larger is a mistake


class UploadError(Exception):
    """Shown to the operator as a flash message, never as a traceback."""


def _service_key() -> str | None:
    """The service-role key. Writing to Storage needs more than the anon key,
    and the console has no reader session to borrow — it is the operator."""
    return (os.getenv("SUPABASE_SERVICE_ROLE_KEY") or "").strip() or None


def _base() -> str | None:
    return (get_settings().supabase_url or "").strip().rstrip("/") or None


def configured() -> bool:
    return bool(_base() and _service_key())


def why_not_configured() -> str:
    missing = []
    if not _base():
        missing.append("SUPABASE_URL")
    if not _service_key():
        missing.append("SUPABASE_SERVICE_ROLE_KEY")
    return "Uploads are off — missing " + ", ".join(missing)


def public_url(path: str) -> str:
    return f"{_base()}/storage/v1/object/public/{BUCKET}/{path}"


async def upload_image(folder: str, filename: str, body: bytes, content_type: str | None) -> str:
    """Store one image and return the public URL it will be served from.

    `folder` matches the app's convention ("publishers", "authors",
    "campaigns"); the object name is a uuid, so re-uploading never overwrites —
    the old object is orphaned rather than swapped under a URL something else
    may still reference.
    """
    if not configured():
        raise UploadError(why_not_configured())
    if not body:
        raise UploadError("That file was empty.")
    if len(body) > MAX_BYTES:
        raise UploadError(f"Too large — keep it under {MAX_BYTES // 1024 // 1024} MB.")

    # Trust the extension over the browser's Content-Type, which is routinely
    # application/octet-stream from a drag-and-drop.
    suffix = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""
    by_suffix = {v: k for k, v in ALLOWED.items()} | {".jpeg": "image/jpeg"}
    resolved = by_suffix.get(suffix) or content_type
    if resolved not in ALLOWED:
        raise UploadError("Only JPEG, PNG, WebP or SVG.")

    path = f"{folder}/{uuid.uuid4().hex}{ALLOWED[resolved]}"
    await _put(path, body, resolved)
    return public_url(path)


async def _put(path: str, body: bytes, content_type: str, *, upsert: bool = False) -> None:
    """One object into the bucket, or an `UploadError` the operator can read."""
    headers = {
        "Authorization": f"Bearer {_service_key()}",
        "Content-Type": content_type,
        "Cache-Control": "public, max-age=31536000, immutable",
    }
    if upsert:
        headers["x-upsert"] = "true"
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{_base()}/storage/v1/object/{BUCKET}/{path}", content=body, headers=headers
            )
    except httpx.HTTPError as exc:
        raise UploadError(f"Upload failed: {exc.__class__.__name__}") from exc
    if resp.status_code >= 400:
        # Storage answers with a JSON body; surface its message, not a status
        # code the operator can do nothing with.
        detail = ""
        try:
            detail = resp.json().get("message") or resp.json().get("error") or ""
        except Exception:  # noqa: BLE001 — a non-JSON error body is still an error
            detail = resp.text[:120]
        raise UploadError(f"Upload rejected ({resp.status_code}): {detail}")


# ---------------------------------------------------------------------------
# Book covers.
#
# A cover is not stored as it arrives. It goes through `cover_ingest.normalize`
# — the same step every cover the nightly intake publishes goes through —
# which decodes it with only the four decoders a cover arrives in, turns a
# phone photo upright, refuses anything too small or not book-shaped, shrinks
# it to 800px and re-encodes it as JPEG. That last step is also what strips
# EXIF (a phone photo's GPS position among it) and anything else riding along,
# and it is what keeps a 4 MB scan from costing Supabase egress on every view
# (the egress meter that ran over on 7 Sep 2026).
#
# Stored in the app's own `covers/` folder, so an operator's cover and a
# reader's are the same kind of object. Content-addressed rather than a random
# name: the same picture is always the same URL, so a double-submit writes one
# object and the `immutable` cache header stays true.
# ---------------------------------------------------------------------------

COVER_FOLDER = "covers"

# Who is asking, when a pasted link is fetched. Big image hosts (Wikimedia among
# them) refuse a request with no real User-Agent — found trying this live, a
# 403 on the first link pasted. Same shape as the nightly intake's own
# (`jobs/catalog_intake.USER_AGENT`), so a site sees one Kitabi, not two.
USER_AGENT = "Kitabi/1.0 (+https://kitabi.in; admin console)"


class CoverError(UploadError):
    """A cover we will not store — shown to the operator as a flash message."""


def cover_url_is_ours(url: str | None) -> bool:
    """A URL the catalogue may point at as it is: our Supabase bucket, the R2
    covers bucket, or covers.openlibrary.org (the one third-party host the web
    and the app already serve). The same rule the intake publishes by."""
    return cover_ingest.servable_as_is(get_settings(), url)


async def store_cover(body: bytes) -> str:
    """Normalise one cover image and store it; return its public URL."""
    if not configured():
        raise CoverError(why_not_configured())
    if not body:
        raise CoverError("That file was empty.")
    if len(body) > cover_ingest.MAX_SOURCE_BYTES:
        mb = cover_ingest.MAX_SOURCE_BYTES // 1024 // 1024
        raise CoverError(f"Too large — keep it under {mb} MB.")
    # Pillow is synchronous: decode on a worker thread so one large scan never
    # stalls every other page the console is serving.
    normalized = await asyncio.to_thread(cover_ingest.normalize, body)
    if normalized is None:
        raise CoverError(
            "That isn't a usable cover. It needs to be a JPEG, PNG, WebP or GIF, at least "
            f"{cover_ingest.MIN_EDGE}px on its longest side, and roughly book-shaped."
        )
    path = f"{COVER_FOLDER}/{hashlib.sha256(normalized).hexdigest()[:32]}.jpg"
    await _put(path, normalized, "image/jpeg", upsert=True)
    return public_url(path)


async def cover_from_url(url: str) -> str:
    """A cover from a link the operator pasted.

    A URL that is already ours is taken as it is — which is also how a removal
    or a replacement is undone: the audit log keeps the old URL, and pasting it
    back here restores it, with or without uploads configured. Anything else is
    fetched the way the intake fetches a publisher's cover (https only, a
    public hostname, every redirect re-checked, the body capped), then
    normalised and stored like an upload — so the catalogue never ends up
    pointing at somebody else's server.
    """
    url = (url or "").strip()
    if not url:
        raise CoverError("Paste a link to an image, or choose a file.")
    if cover_url_is_ours(url):
        return url
    if not cover_ingest.safe_source(url):
        raise CoverError("Only https:// links to an image on a public website.")
    if not configured():
        raise CoverError(why_not_configured())
    async with httpx.AsyncClient(timeout=20, headers={"User-Agent": USER_AGENT}) as client:
        # The intake's own vetted fetch: per-hop URL checks, image types only,
        # a streamed size cap. Private by name, reused rather than copied so
        # the two can't drift — and read-only here, so nothing the intake
        # publishes changes because the console calls it.
        fetched = await cover_ingest._fetch(client, url)  # noqa: SLF001
    if fetched.gone:
        raise CoverError(
            "Couldn't get an image from that link — it isn't there, or isn't an image."
        )
    if not fetched.body:
        raise CoverError(
            "That site wouldn't hand the image over, or didn't answer. Try again in a minute, "
            "or save the picture and upload the file instead."
        )
    return await store_cover(fetched.body)
