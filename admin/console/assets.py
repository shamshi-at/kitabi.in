"""Image uploads to Cloudflare R2 — publisher logos and campaign artwork.

**No new service and no new bill** (CLAUDE.md rule 8): R2 is already in the
stack for the nightly encrypted `pg_dump` (`.github/workflows/backup.yml`), and
this reuses the same account and the same four credentials. Its free tier is
10 GB with no egress charge; these images are kilobytes.

**Dormant until configured**, exactly like `console/mail.py` and the Anthropic
key: with no credentials, `configured()` is False, the console hides the upload
control and says to paste a URL instead. Nothing breaks, nothing 500s, and the
feature simply isn't offered.

Uploads run on a worker thread — boto3 is synchronous, and blocking the event
loop of a single-replica console while a file goes over the wire would stall
every other request.
"""

import asyncio
import mimetypes
import os
import uuid

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


def _env(name: str) -> str | None:
    return (os.getenv(name) or "").strip() or None


def configured() -> bool:
    """True when every piece needed to upload *and* serve is present.

    `R2_PUBLIC_BASE_URL` is part of it: a bucket we can write to but can't hand
    out a URL for is useless here, and finding that out after the upload would
    leave an orphaned object and a broken image.
    """
    return all(
        _env(k)
        for k in (
            "R2_ACCESS_KEY_ID",
            "R2_SECRET_ACCESS_KEY",
            "R2_ENDPOINT",
            "R2_PROMO_BUCKET",
            "R2_PUBLIC_BASE_URL",
        )
    )


def why_not_configured() -> str:
    missing = [
        k
        for k in (
            "R2_ACCESS_KEY_ID",
            "R2_SECRET_ACCESS_KEY",
            "R2_ENDPOINT",
            "R2_PROMO_BUCKET",
            "R2_PUBLIC_BASE_URL",
        )
        if not _env(k)
    ]
    return "Uploads are off — missing " + ", ".join(missing)


def _client():
    import boto3  # noqa: PLC0415 — imported lazily so the console runs without it

    return boto3.client(
        "s3",
        endpoint_url=_env("R2_ENDPOINT"),
        aws_access_key_id=_env("R2_ACCESS_KEY_ID"),
        aws_secret_access_key=_env("R2_SECRET_ACCESS_KEY"),
        region_name="auto",  # R2 ignores regions but boto3 insists on one
    )


def _put(key: str, body: bytes, content_type: str) -> None:
    _client().put_object(
        Bucket=_env("R2_PROMO_BUCKET"),
        Key=key,
        Body=body,
        ContentType=content_type,
        # A year: the key carries a uuid, so a changed image is a new key and
        # nothing has to be purged from anyone's cache.
        CacheControl="public, max-age=31536000, immutable",
    )


async def upload_image(prefix: str, filename: str, body: bytes, content_type: str | None) -> str:
    """Store one image and return the public URL it will be served from.

    `prefix` groups objects by what they are ("publishers", "campaigns") so the
    bucket stays legible; the key itself is a uuid, so re-uploading never
    overwrites — the old object is simply orphaned rather than swapped under a
    URL something else may still reference.
    """
    if not configured():
        raise UploadError(why_not_configured())
    if not body:
        raise UploadError("That file was empty.")
    if len(body) > MAX_BYTES:
        raise UploadError(f"Too large — keep it under {MAX_BYTES // 1024 // 1024} MB.")

    # Trust the sniffed extension over the browser's Content-Type, which is
    # routinely application/octet-stream from a drag-and-drop.
    guessed = mimetypes.guess_type(filename)[0]
    resolved = guessed if guessed in ALLOWED else content_type
    if resolved not in ALLOWED:
        raise UploadError("Only JPEG, PNG, WebP or SVG.")

    key = f"{prefix}/{uuid.uuid4().hex}{ALLOWED[resolved]}"
    try:
        await asyncio.to_thread(_put, key, body, resolved)
    except UploadError:
        raise
    except Exception as exc:  # noqa: BLE001 — surfaced to the operator, not raised
        raise UploadError(f"Upload failed: {exc.__class__.__name__}") from exc
    return f"{_env('R2_PUBLIC_BASE_URL').rstrip('/')}/{key}"
