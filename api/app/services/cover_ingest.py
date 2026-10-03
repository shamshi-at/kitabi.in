"""Turn a cover somewhere on the internet into a cover we own.

The step between "a source says this book's cover is at this URL" and "the
catalogue points at it". Three things happen, in this order, and a book is not
published until all three have:

1. **Fetch** the image from the source — vetted, capped, and with every
   redirect vetted again.
2. **Normalise** it: longest edge 800px, JPEG, quality 80. A publisher's own
   cover art measured ~600 KB (mbibooks.com, 9 Sep 2026); this brings it to
   ~50 KB, which is the difference between 12,000 covers costing 7 GB and
   costing 600 MB.
3. **Store** it in the R2 covers bucket (`r2_client`) under a key derived from
   the bytes, and hand back that URL.

Owning the cover rather than hotlinking it is a decision `cover_storage`
already made and explains ("a cache is not ownership"). What is new here is
*where* (R2, owner decision 3 Oct 2026 — docs/catalog-intake-plan.md §4) and
that it happens **before** the book exists rather than as a backfill after:
the intake gate's promise is that a record is complete or it is not created,
and a cover that turns out not to load is not complete.

**Three outcomes, never two.** `Ingested.url` is set, or `gone` is true (this
URL will never be a usable cover — stop asking), or neither (we could not tell
right now — ask again). It is the same split `cover_storage.Fetched` makes and
for the same reason: collapse "gone" into "transient" and a dead cover is
retried forever; collapse it the other way and one bad minute at a publisher's
CDN costs a book its cover.
"""

from __future__ import annotations

import asyncio
import hashlib
import io
import ipaddress
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit

import httpx
from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.config import Settings
from app.services import cover_storage, r2_client

#: Where ingested covers land in the bucket. The same folder name
#: `cover_storage` uses in Supabase, so "catalog/" means the same thing in
#: both stores.
FOLDER = "catalog"

#: Longest edge of what we keep. The largest a cover is ever drawn is the
#: lightbox on a phone; 800px covers that at 2× and is what the plan sized
#: storage against.
MAX_EDGE = 800
JPEG_QUALITY = 80

#: Smaller than this on its longest edge is not cover art — it is a tracking
#: pixel, a "no image" thumbnail, or OpenLibrary's 1×1 GIF for a missing cover.
#: Storing it would satisfy the gate with a picture nobody can read.
MIN_EDGE = 200
#: Width ÷ height bounds. Generous on purpose — square picture books and
#: landscape atlases are real — but a 1200×300 banner is a site header, not a
#: cover, and a storefront's placeholder is often exactly that.
MIN_ASPECT = 1 / 3
MAX_ASPECT = 2.0

#: Refuse to decode anything larger. Checked from the header, before a single
#: pixel is decompressed, so a small file claiming enormous dimensions costs
#: nothing. A 600-dpi scan of a 6×9" cover is ~19 MP; this leaves room above
#: that while keeping the worst case — decoded inside the API process, at
#: three bytes a pixel — well under a hundred megabytes.
MAX_PIXELS = 25_000_000
#: The source file. Larger than `cover_storage.MAX_BYTES` because this path
#: resizes, so an oversized original is input rather than something to serve.
MAX_SOURCE_BYTES = 12 * 1024 * 1024

#: Only these decoders are ever invoked. Pillow ships dozens; an image proxy
#: that will parse any of them is a much larger attack surface than one that
#: parses the four formats a cover actually arrives in.
_FORMATS = ("JPEG", "PNG", "WEBP", "GIF")

MAX_REDIRECTS = 3
#: Between fetches, so a night's promotions never arrive at one publisher's
#: site as a burst. The same figure `backfill_covers` settled on.
PAUSE_SECONDS = 0.3

_BLOCKED_SUFFIXES = (".internal", ".local", ".localhost", ".lan", ".home", ".corp")


@dataclass(frozen=True)
class Ingested:
    """One cover's outcome. See the module docstring for the three cases."""

    url: str | None = None
    gone: bool = False
    #: Why, for the intake row's note. Never shown to a reader.
    reason: str | None = None


#: What `intake_service.promote` is handed: a source URL in, a verdict out.
Ingester = Callable[[str], Awaitable[Ingested]]


def safe_source(url: str | None) -> bool:
    """Whether this is a URL we are willing to fetch from a server.

    The URL came out of a third party's feed, and this process runs inside our
    network. So: https only, the default port only, no credentials, and a real
    public-looking hostname — not an IP literal, not `localhost`, not a
    private-network suffix. This does not resolve the name (a hostname can
    still be pointed at a private address); what bounds that case is that the
    response is only ever decoded as an image and re-encoded, so the most a
    hostile URL can extract is a picture.
    """
    if not url or len(url) > 2000:
        return False
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        return False
    if parts.scheme != "https" or parts.username or parts.password:
        return False
    if port not in (None, 443):
        return False
    host = (parts.hostname or "").lower().rstrip(".")
    if not host or "." not in host or host.endswith(_BLOCKED_SUFFIXES):
        return False
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return True
    return False  # an IP literal, public or not, is never a publisher's CDN


def normalize(body: bytes) -> bytes | None:
    """Decode, flatten, shrink and re-encode as JPEG — or None if this is not
    a usable cover.

    Pure and synchronous (CPU-bound); callers run it in a thread. Re-encoding
    is also what strips EXIF, colour profiles and anything else riding along in
    the original, so what we serve is pixels and nothing else.
    """
    try:
        with Image.open(io.BytesIO(body), formats=_FORMATS) as source:
            width, height = source.size
            if width * height > MAX_PIXELS:
                return None
            # JPEG only, a no-op elsewhere: have the decoder itself hand back a
            # half/quarter/eighth-size image, never smaller than twice what we
            # keep. A 20 MP print file then costs a fraction of the memory and
            # time, and the final resize still has pixels to spare.
            source.draft(None, (MAX_EDGE * 2, MAX_EDGE * 2))
            # An animated GIF/WebP is taken at its first frame, which is where
            # `open` leaves it. A phone photo is rotated to how it was held.
            image = ImageOps.exif_transpose(source)
            if image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info):
                # Transparency over white, not the black JPEG would give it —
                # a die-cut cover on a black slab reads as a broken image.
                rgba = image.convert("RGBA")
                image = Image.new("RGB", rgba.size, (255, 255, 255))
                image.paste(rgba, mask=rgba.getchannel("A"))
            else:
                image = image.convert("RGB")  # CMYK, greyscale, palette → RGB

            width, height = image.size
            if max(width, height) < MIN_EDGE or not (MIN_ASPECT <= width / height <= MAX_ASPECT):
                return None
            # `thumbnail` only ever shrinks: a 500px cover stays 500px rather
            # than being blown up into a blurrier, larger file.
            image.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
            out = io.BytesIO()
            image.save(out, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
            return out.getvalue()
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError, SyntaxError):
        # Truncated, corrupt, not one of `_FORMATS`, or not an image at all.
        return None


def object_key(body: bytes) -> str:
    """Content-addressed: the same picture is always the same object.

    That makes a retried promotion idempotent (it lands on the object it wrote
    last time instead of orphaning it), and it is what makes the `immutable`
    cache header true — different art cannot appear under a URL a phone has
    already cached, because different art is a different URL.
    """
    return f"{FOLDER}/{hashlib.sha256(body).hexdigest()[:32]}.jpg"


async def _fetch(client: httpx.AsyncClient, url: str) -> cover_storage.Fetched:
    """`cover_storage.fetch_cover`'s verdicts, with two differences this path
    needs: every redirect hop is vetted before it is followed, and the body is
    streamed against a cap rather than read whole."""
    for _ in range(MAX_REDIRECTS + 1):
        if not safe_source(url):
            return cover_storage.Fetched(gone=True)
        try:
            async with client.stream(
                "GET", url, headers={"Accept": "image/*"}, follow_redirects=False
            ) as resp:
                if resp.status_code in (301, 302, 303, 307, 308):
                    location = resp.headers.get("location")
                    if not location:
                        return cover_storage.Fetched(gone=True)
                    url = urljoin(url, location)
                    continue
                if resp.status_code in (404, 410):
                    return cover_storage.Fetched(gone=True)
                if resp.status_code >= 400:
                    return cover_storage.Fetched()  # 5xx, 429, 403 — ask again
                content_type = (
                    (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
                )
                if content_type not in cover_storage.ALLOWED:
                    # A storefront answers a missing image with its HTML 404
                    # page and a 200 as often as with a 404.
                    return cover_storage.Fetched(gone=True)
                chunks: list[bytes] = []
                size = 0
                async for chunk in resp.aiter_bytes():
                    size += len(chunk)
                    if size > MAX_SOURCE_BYTES:
                        return cover_storage.Fetched(gone=True)
                    chunks.append(chunk)
                body = b"".join(chunks)
                return cover_storage.Fetched(
                    body=body or None, content_type=content_type, gone=not body
                )
        except httpx.HTTPError:
            return cover_storage.Fetched()  # transient — leave it for next run
    return cover_storage.Fetched(gone=True)  # a redirect loop is not a cover


async def ingest(
    client: httpx.AsyncClient,
    settings: Settings,
    url: str,
    *,
    pause: float = PAUSE_SECONDS,
) -> Ingested:
    """Fetch → normalise → store. Never raises."""
    if not safe_source(url):
        return Ingested(gone=True, reason="cover URL is not one we will fetch")

    fetched = await _fetch(client, url)
    if pause:
        await asyncio.sleep(pause)
    if fetched.gone:
        return Ingested(gone=True, reason="cover is not there, or is not an image")
    if not fetched.body:
        return Ingested(reason="cover source did not answer")

    # Pillow is synchronous and this runs inside the API process: decode on a
    # worker thread so a large cover never stalls a reader's request.
    normalized = await asyncio.to_thread(normalize, fetched.body)
    if normalized is None:
        return Ingested(gone=True, reason="cover is unreadable, too small, or not cover-shaped")

    stored = await r2_client.put_object(
        client, settings, object_key(normalized), normalized, "image/jpeg"
    )
    if stored is None:
        return Ingested(reason="cover storage did not accept the upload")
    return Ingested(url=stored)


def ingester(
    client: httpx.AsyncClient, settings: Settings, *, pause: float = PAUSE_SECONDS
) -> Ingester | None:
    """The callable `promote` takes — or None when R2 is not configured, which
    `promote` reads as "there is nowhere to put a cover"."""
    if not r2_client.configured(settings):
        return None

    async def run(url: str) -> Ingested:
        return await ingest(client, settings, url, pause=pause)

    return run


def is_ours(settings: Settings, url: str | None) -> bool:
    """Already in one of our two stores — the R2 covers bucket, or the Supabase
    bucket reader uploads and the first seed's backfilled covers live in."""
    return r2_client.is_ours(settings, url) or cover_storage.is_ours(settings, url)


def servable_as_is(settings: Settings, url: str | None) -> bool:
    """Whether the catalogue may point straight at this URL without ingesting.

    True for a cover already in one of our two stores, and for
    covers.openlibrary.org — the one third-party host the edge proxy and the
    app already serve, and which `backfill_covers` later brings home. Anything
    else is a host no client has been told about.
    """
    if not url:
        return False
    return is_ours(settings, url) or url.startswith("https://covers.openlibrary.org/")
