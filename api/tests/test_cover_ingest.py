"""Fetch → normalise → store: turning a source's cover into one we own.

Two things carry the weight here. **What counts as a cover** — the gate
requires one, so anything this lets through satisfies it: a tracking pixel or
a site banner stored as cover art is a complete-looking record that is wrong.
And **gone vs. transient**, the same split `test_cover_backfill` is built
around: a dead image must stop being asked for, and a busy CDN must not cost a
book its cover.
"""

import io

import httpx
import pytest
from PIL import Image

from app.core.config import get_settings
from app.services import cover_ingest

PUBLIC = "https://covers.kitabi.in"
SOURCE = "https://www.mbibooks.com/wp-content/uploads/cover.jpg"


def _settings(**over):
    return get_settings().model_copy(
        update={
            "r2_account_id": "acct123",
            "r2_access_key_id": "AKID",
            "r2_secret_access_key": "SECRET",
            "r2_covers_bucket": "kitabi-covers",
            "r2_covers_public_url": PUBLIC,
            "supabase_url": "https://proj.supabase.co",
            **over,
        }
    )


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=5)


def picture(size=(1200, 1800), mode="RGB", fmt="JPEG", color=(120, 30, 40), **save) -> bytes:
    """A real, decodable image — noisy enough that it does not compress to
    nothing, so byte-size assertions mean something."""
    image = Image.effect_noise(size, 64).convert("RGB")
    tint = Image.new("RGB", size, color)
    image = Image.blend(image, tint, 0.5)
    if mode != "RGB":
        image = image.convert(mode)
    out = io.BytesIO()
    image.save(out, fmt, **save)
    return out.getvalue()


def decoded(body: bytes) -> Image.Image:
    return Image.open(io.BytesIO(body))


def _is_r2(request) -> bool:
    return request.url.host.endswith("r2.cloudflarestorage.com")


def source_then_bucket(source_response, uploads=None):
    """A transport that answers the cover source with `source_response` and
    accepts whatever is PUT to the bucket."""

    def handler(request):
        if _is_r2(request):
            if uploads is not None:
                uploads.append(request)
            return httpx.Response(200)
        return source_response(request) if callable(source_response) else source_response

    return handler


def image_response(body, content_type="image/jpeg"):
    return httpx.Response(200, content=body, headers={"content-type": content_type})


# --------------------------------------------------------------------------
# normalize — what we keep
# --------------------------------------------------------------------------


def test_a_large_cover_is_shrunk_to_800px_jpeg():
    """The whole reason this step exists: a publisher's ~600 KB original
    becomes something a phone can load over a bad connection."""
    original = picture((1600, 2400), quality=95)
    out = cover_ingest.normalize(original)

    image = decoded(out)
    assert image.format == "JPEG"
    assert max(image.size) == cover_ingest.MAX_EDGE
    assert image.size == (533, 800)  # aspect kept
    assert len(out) < len(original) / 4


def test_a_small_cover_is_never_enlarged():
    """Upscaling makes a blurrier picture in a bigger file."""
    out = cover_ingest.normalize(picture((300, 450)))
    assert decoded(out).size == (300, 450)


def test_transparency_is_flattened_onto_white_not_black():
    """JPEG has no alpha, and Pillow's default drops it onto black — a die-cut
    cover on a black slab reads as a broken image."""
    image = Image.new("RGBA", (400, 600), (0, 0, 0, 0))
    out = io.BytesIO()
    image.save(out, "PNG")
    result = decoded(cover_ingest.normalize(out.getvalue())).convert("RGB")
    assert all(channel > 240 for channel in result.getpixel((200, 300)))


def test_a_cmyk_jpeg_from_a_print_workflow_becomes_rgb():
    """Publishers export covers from print files; browsers render CMYK JPEGs
    with inverted or washed-out colour, when they render them at all."""
    out = cover_ingest.normalize(picture((400, 600), mode="CMYK"))
    assert decoded(out).mode == "RGB"


def test_a_palette_png_and_a_webp_are_both_read():
    assert cover_ingest.normalize(picture((400, 600), mode="P", fmt="PNG")) is not None
    assert cover_ingest.normalize(picture((400, 600), fmt="WEBP")) is not None


def test_a_phone_photo_is_rotated_to_how_it_was_held():
    """EXIF orientation is metadata, and re-encoding strips metadata — so the
    rotation has to be applied to the pixels first or the cover lands sideways."""
    image = Image.effect_noise((600, 400), 64).convert("RGB")  # stored landscape…
    exif = Image.Exif()
    exif[0x0112] = 6  # …with "rotate 90° to display"
    out = io.BytesIO()
    image.save(out, "JPEG", exif=exif)
    result = decoded(cover_ingest.normalize(out.getvalue()))
    assert result.size == (400, 600)
    assert not result.getexif()  # and nothing rides along in what we serve


# --------------------------------------------------------------------------
# normalize — what we refuse
# --------------------------------------------------------------------------


@pytest.mark.parametrize("size", [(1, 1), (60, 90), (199, 150)])
def test_a_tracking_pixel_or_thumbnail_is_not_a_cover(size):
    """OpenLibrary answers a missing cover with a 1×1 GIF. Stored, that would
    satisfy the gate with a picture nobody can see."""
    assert cover_ingest.normalize(picture(size, fmt="PNG")) is None


@pytest.mark.parametrize("size", [(1200, 300), (200, 900)])
def test_a_banner_is_not_a_cover(size):
    assert cover_ingest.normalize(picture(size)) is None


def test_a_square_picture_book_and_a_landscape_atlas_are_covers():
    assert cover_ingest.normalize(picture((600, 600))) is not None
    assert cover_ingest.normalize(picture((800, 600))) is not None


@pytest.mark.parametrize(
    "body",
    [b"", b"<html>not found</html>", b"\x89PNG\r\n\x1a\n" + b"x" * 64, picture((400, 600))[:200]],
    ids=["empty", "html", "png-magic-then-junk", "truncated-jpeg"],
)
def test_bytes_that_do_not_decode_are_refused_not_raised(body):
    assert cover_ingest.normalize(body) is None


def test_a_decompression_bomb_is_refused_from_its_header(monkeypatch):
    """A few kilobytes can claim to be a hundred megapixels. The size is read
    from the header and refused before anything is decompressed."""
    monkeypatch.setattr(cover_ingest, "MAX_PIXELS", 1000)
    assert cover_ingest.normalize(picture((400, 600))) is None


def test_a_format_outside_the_four_we_accept_is_not_decoded():
    """Pillow can parse dozens of formats; only JPEG, PNG, WebP and GIF are
    ever handed to a decoder."""
    out = io.BytesIO()
    Image.new("RGB", (400, 600)).save(out, "BMP")
    assert cover_ingest.normalize(out.getvalue()) is None


# --------------------------------------------------------------------------
# The object key
# --------------------------------------------------------------------------


def test_the_key_is_derived_from_the_bytes():
    """Same picture, same object — a retried promotion lands where it landed
    last time. Different picture, different URL — which is what makes
    `immutable` true."""
    a, b = b"one cover", b"another cover"
    assert cover_ingest.object_key(a) == cover_ingest.object_key(a)
    assert cover_ingest.object_key(a) != cover_ingest.object_key(b)
    assert cover_ingest.object_key(a).startswith("catalog/")
    assert cover_ingest.object_key(a).endswith(".jpg")


# --------------------------------------------------------------------------
# Which URLs we will fetch at all
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "url",
    [
        "https://www.mbibooks.com/wp-content/uploads/a.jpg",
        "https://covers.openlibrary.org/b/id/1-L.jpg",
        "https://cdn.shopify.com/s/files/1/a.jpg?v=1",
        "https://harpercollins.co.in:443/a.jpg",
    ],
)
def test_an_ordinary_public_https_url_is_fetchable(url):
    assert cover_ingest.safe_source(url) is True


@pytest.mark.parametrize(
    "url",
    [
        "http://www.mbibooks.com/a.jpg",  # no downgrade
        "https://127.0.0.1/a.jpg",
        "https://10.0.0.5/a.jpg",
        "https://169.254.169.254/latest/meta-data",  # cloud metadata
        "https://[::1]/a.jpg",
        "https://93.184.216.34/a.jpg",  # even a public IP is not a publisher
        "https://localhost/a.jpg",
        "https://api.railway.internal/a.jpg",
        "https://printer.local/a.jpg",
        "https://intranet/a.jpg",  # no dot: a bare internal name
        "https://user:pw@www.mbibooks.com/a.jpg",
        "https://www.mbibooks.com:8443/a.jpg",
        "file:///etc/passwd",
        "ftp://www.mbibooks.com/a.jpg",
        "https://",
        "",
        None,
    ],
)
def test_anything_else_is_never_fetched(url):
    """These URLs arrive in a third party's feed and are fetched from inside
    our network."""
    assert cover_ingest.safe_source(url) is False


# --------------------------------------------------------------------------
# ingest — the three outcomes
# --------------------------------------------------------------------------


async def test_a_good_cover_is_stored_shrunk_and_the_catalogue_gets_our_url():
    uploads = []
    original = picture((1600, 2400), quality=95)
    async with _client(source_then_bucket(image_response(original), uploads)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)

    assert result.url is not None and result.url.startswith(f"{PUBLIC}/catalog/")
    assert result.gone is False
    (upload,) = uploads
    assert upload.method == "PUT"
    assert upload.headers["content-type"] == "image/jpeg"
    stored = decoded(upload.content)
    assert max(stored.size) == 800
    # The URL names exactly the bytes that were stored.
    assert result.url == f"{PUBLIC}/{cover_ingest.object_key(upload.content)}"
    assert str(upload.url).endswith(cover_ingest.object_key(upload.content))


async def test_the_same_cover_twice_lands_on_the_same_object():
    original = picture((900, 1350))
    async with _client(source_then_bucket(image_response(original))) as c:
        first = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
        second = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert first.url == second.url


@pytest.mark.parametrize("status", [404, 410])
async def test_a_missing_cover_is_gone(status):
    async with _client(source_then_bucket(httpx.Response(status))) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is True and result.url is None


@pytest.mark.parametrize("status", [429, 500, 502, 503, 403])
async def test_a_busy_or_refusing_source_is_transient_not_gone(status):
    """429 especially: being rate-limited must never be read as "this book has
    no cover"."""
    async with _client(source_then_bucket(httpx.Response(status))) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is False and result.url is None


async def test_a_network_failure_is_transient():
    def boom(request):
        raise httpx.ConnectError("no route")

    async with _client(boom) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is False and result.url is None


async def test_an_html_page_served_with_200_is_gone():
    """A storefront answers a missing image with its 404 *page* and a 200 as
    often as with a 404."""
    response = httpx.Response(200, content=b"<html/>", headers={"content-type": "text/html"})
    async with _client(source_then_bucket(response)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is True


async def test_an_image_that_is_not_a_usable_cover_is_gone_and_never_uploaded():
    uploads = []
    pixel = picture((1, 1), fmt="GIF")
    async with _client(source_then_bucket(image_response(pixel, "image/gif"), uploads)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is True
    assert uploads == []


async def test_an_oversized_source_is_abandoned_mid_download(monkeypatch):
    monkeypatch.setattr(cover_ingest, "MAX_SOURCE_BYTES", 1000)
    uploads = []
    async with _client(source_then_bucket(image_response(picture((900, 1350))), uploads)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is True
    assert uploads == []


async def test_a_failed_upload_is_transient_so_the_cover_is_tried_again():
    """The picture was fine; our bucket was not. That must not mark the cover
    dead."""

    def handler(request):
        if _is_r2(request):
            return httpx.Response(503)
        return image_response(picture((900, 1350)))

    async with _client(handler) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.url is None and result.gone is False


async def test_an_unsafe_url_is_refused_without_a_request():
    def explode(request):
        raise AssertionError("an unsafe URL must never be fetched")

    async with _client(explode) as c:
        result = await cover_ingest.ingest(c, _settings(), "https://169.254.169.254/x", pause=0)
    assert result.gone is True


# --------------------------------------------------------------------------
# Redirects — vetted hop by hop
# --------------------------------------------------------------------------


async def test_a_redirect_to_another_public_host_is_followed():
    """A storefront's image URL commonly bounces to its CDN."""
    body = picture((900, 1350))

    def source(request):
        if request.url.host == "www.mbibooks.com":
            return httpx.Response(302, headers={"location": "https://cdn.mbibooks.com/c.jpg"})
        return image_response(body)

    async with _client(source_then_bucket(source)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.url is not None


@pytest.mark.parametrize(
    "location",
    ["http://www.mbibooks.com/c.jpg", "https://169.254.169.254/x", "https://db.internal/x"],
)
async def test_a_redirect_somewhere_we_would_not_fetch_is_not_followed(location):
    """Vetting only the first URL is no vetting at all: the feed's URL is
    public, and the place it redirects to need not be."""
    hops = []

    def source(request):
        hops.append(str(request.url))
        return httpx.Response(302, headers={"location": location})

    async with _client(source_then_bucket(source)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is True
    assert hops == [SOURCE]  # the redirect target was never requested


async def test_a_redirect_loop_gives_up():
    hops = []

    def source(request):
        hops.append(1)
        return httpx.Response(302, headers={"location": SOURCE})

    async with _client(source_then_bucket(source)) as c:
        result = await cover_ingest.ingest(c, _settings(), SOURCE, pause=0)
    assert result.gone is True
    assert len(hops) == cover_ingest.MAX_REDIRECTS + 1


# --------------------------------------------------------------------------
# The dormancy gate, and what may be published without ingesting
# --------------------------------------------------------------------------


def test_there_is_no_ingester_without_r2():
    """Rule 8: unconfigured means dormant — `promote` is handed None and
    nothing here can make a request."""
    assert cover_ingest.ingester(httpx.AsyncClient(), _settings()) is not None
    assert cover_ingest.ingester(httpx.AsyncClient(), _settings(r2_covers_bucket="")) is None


def test_only_our_own_stores_and_openlibrary_are_servable_as_is():
    s = _settings()
    assert cover_ingest.servable_as_is(s, f"{PUBLIC}/catalog/abc.jpg")
    assert cover_ingest.servable_as_is(
        s, "https://proj.supabase.co/storage/v1/object/public/covers/catalog/x.jpg"
    )
    assert cover_ingest.servable_as_is(s, "https://covers.openlibrary.org/b/id/1-L.jpg")
    # A publisher's own site is a host no client has been told about.
    assert not cover_ingest.servable_as_is(s, SOURCE)
    assert not cover_ingest.servable_as_is(s, "https://covers.openlibrary.org.evil.test/x.jpg")
    assert not cover_ingest.servable_as_is(s, None)
