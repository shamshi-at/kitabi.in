"""Image uploads — publisher logos, author portraits and campaign artwork.

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

import os
import uuid

import httpx
from app.core.config import get_settings

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
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{_base()}/storage/v1/object/{BUCKET}/{path}",
                content=body,
                headers={
                    "Authorization": f"Bearer {_service_key()}",
                    "Content-Type": resolved,
                    "Cache-Control": "public, max-age=31536000, immutable",
                },
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
    return public_url(path)
