"""Move a hotlinked cover into our own Supabase Storage bucket.

The edge proxy (`landing-page/functions/img/c.js`) already means a reader never
waits on covers.openlibrary.org — but a cache is not ownership. If OpenLibrary
removes an image, changes a URL, or is simply down when an edge entry expires,
the cover is gone. This copies it once into the bucket we already own, and the
catalogue then points at us.

**The same public `covers` bucket the app and the admin console already use**
(CLAUDE.md: that bucket, never a second store — a second store is a second
credential and a second thing to reason about). The upload shape mirrors
`admin/console/assets.py`; it isn't imported because that lives in a separate
service and deployable.

**Dormant without `SUPABASE_SERVICE_ROLE_KEY`**, the same gate as recommendations
and push (rule 8): unset means the backfill does nothing and no external call is
made. Writing to Storage needs more than the anon key.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

import httpx

from app.core.config import Settings, get_settings

BUCKET = "covers"
# Where migrated catalogue covers land. A folder of their own, so they're
# distinguishable from reader uploads ("authors/", "publishers/", "campaigns/").
FOLDER = "catalog"

# Only what a browser will render and we're willing to serve back.
ALLOWED: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}
# A book cover. Anything larger is a scan or a mistake, and not worth storing.
MAX_BYTES = 3 * 1024 * 1024


@dataclass(frozen=True)
class Fetched:
    """One downloaded cover, or a verdict about why there isn't one.

    `gone` distinguishes "this image does not exist" (a definitive 404/410 —
    stop asking) from "we could not get it right now" (a timeout, a 5xx, a rate
    limit — try again later). Collapsing those two is how a backfill either
    hammers a third party forever or discards covers over one bad minute.
    """

    body: bytes | None = None
    content_type: str | None = None
    gone: bool = False


def configured(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    return bool(settings.supabase_url and settings.supabase_service_role_key)


def public_url(settings: Settings, path: str) -> str:
    base = settings.supabase_url.rstrip("/")
    return f"{base}/storage/v1/object/public/{BUCKET}/{path}"


def is_ours(settings: Settings, url: str | None) -> bool:
    """Already in our bucket — nothing to do. Checked before every fetch, which
    is what makes the whole job idempotent and cheap to re-run."""
    if not url or not settings.supabase_url:
        return False
    return url.startswith(f"{settings.supabase_url.rstrip('/')}/storage/v1/object/public/")


async def fetch_cover(client: httpx.AsyncClient, url: str) -> Fetched:
    """Download one cover, vetting what comes back."""
    try:
        resp = await client.get(url, headers={"Accept": "image/*"}, follow_redirects=True)
    except httpx.HTTPError:
        return Fetched()  # transient — leave it for the next run

    if resp.status_code in (404, 410):
        return Fetched(gone=True)
    if resp.status_code >= 400:
        return Fetched()

    content_type = (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
    if content_type not in ALLOWED:
        # OpenLibrary answers a missing cover with a 1×1 GIF or an HTML page
        # rather than a 404, so "not an image we want" is also "there is no
        # cover here" — otherwise these rows are retried forever.
        return Fetched(gone=True)
    body = resp.content
    if not body or len(body) > MAX_BYTES:
        return Fetched(gone=not body)
    return Fetched(body=body, content_type=content_type)


async def store_cover(
    client: httpx.AsyncClient,
    settings: Settings,
    key: uuid.UUID,
    body: bytes,
    content_type: str,
) -> str | None:
    """Upload to a path derived from the edition id and return its public URL.

    Deterministic rather than a random object name (which is what the console
    uses for operator uploads): re-running the backfill for the same edition
    must land on the same URL rather than orphaning objects, so the path is the
    id and the write upserts.
    """
    path = f"{FOLDER}/{key}{ALLOWED[content_type]}"
    base = settings.supabase_url.rstrip("/")
    try:
        resp = await client.post(
            f"{base}/storage/v1/object/{BUCKET}/{path}",
            content=body,
            headers={
                "Authorization": f"Bearer {settings.supabase_service_role_key}",
                "Content-Type": content_type,
                "Cache-Control": "public, max-age=31536000, immutable",
                # Idempotent: the same edition always writes the same object.
                "x-upsert": "true",
            },
        )
    except httpx.HTTPError:
        return None
    if resp.status_code >= 400:
        return None
    return public_url(settings, path)
