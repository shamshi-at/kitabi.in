"""Signing and sending the one request we make to Cloudflare R2.

The signer is the part that cannot be eyeballed: a wrong byte anywhere in the
canonical request produces a perfectly well-formed header that the server
refuses. So it is tested against the worked example AWS publishes for a
single-chunk `PUT Object` — real inputs, and the signature AWS says they
produce. Reproducing that is the proof; everything else here is about what we
send and how failure is reported.
"""

from datetime import UTC, datetime

import httpx

from app.core.config import get_settings
from app.services import r2_client

PUBLIC = "https://covers.kitabi.in"


def _settings(**over):
    return get_settings().model_copy(
        update={
            "r2_account_id": "acct123",
            "r2_access_key_id": "AKID",
            "r2_secret_access_key": "SECRET",
            "r2_covers_bucket": "kitabi-covers",
            "r2_covers_public_url": PUBLIC,
            **over,
        }
    )


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=5)


# --------------------------------------------------------------------------
# The signature
# --------------------------------------------------------------------------


def test_the_signer_reproduces_the_published_aws_example():
    """AWS, "Signature Calculations for the Authorization Header: Transferring
    Payload in a Single Chunk" — Example: PUT Object. The key contains a `$`,
    which is what proves the path is URI-encoded exactly once."""
    headers = r2_client.sign(
        method="PUT",
        host="examplebucket.s3.amazonaws.com",
        path="/test$file.text",
        headers={
            "Date": "Fri, 24 May 2013 00:00:00 GMT",
            "x-amz-storage-class": "REDUCED_REDUNDANCY",
        },
        # sha256("Welcome to Amazon S3.")
        payload_hash="44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072",
        access_key="AKIAIOSFODNN7EXAMPLE",
        secret_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        now=datetime(2013, 5, 24, 0, 0, 0, tzinfo=UTC),
    )
    assert headers["Authorization"] == (
        "AWS4-HMAC-SHA256 "
        "Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, "
        "SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class, "
        "Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd"
    )
    assert headers["x-amz-date"] == "20130524T000000Z"
    # The caller's own headers come back untouched, ready to send.
    assert headers["x-amz-storage-class"] == "REDUCED_REDUNDANCY"


def test_a_different_body_is_a_different_signature():
    """The payload hash is signed, so an upload cannot be swapped in flight."""

    def signature(payload_hash):
        return r2_client.sign(
            method="PUT",
            host="h.example",
            path="/b/k.jpg",
            headers={},
            payload_hash=payload_hash,
            access_key="a",
            secret_key="s",
            region="auto",
            now=datetime(2026, 10, 3, tzinfo=UTC),
        )["Authorization"]

    assert signature("a" * 64) != signature("b" * 64)


# --------------------------------------------------------------------------
# The dormancy gate, and recognising our own
# --------------------------------------------------------------------------


def test_dormant_unless_every_setting_is_present():
    """Rule 8's gate. A half-configured bucket must read as *not* configured:
    a missing public URL would otherwise store covers nothing can point at."""
    assert r2_client.configured(_settings()) is True
    for missing in (
        "r2_account_id",
        "r2_access_key_id",
        "r2_secret_access_key",
        "r2_covers_bucket",
        "r2_covers_public_url",
    ):
        assert r2_client.configured(_settings(**{missing: ""})) is False, missing


def test_is_ours_needs_only_the_public_origin():
    """A deployment that can read the catalogue but holds no bucket keys must
    still recognise an R2 cover as ours — the backfill depends on it."""
    s = _settings(r2_access_key_id="", r2_secret_access_key="")
    assert r2_client.is_ours(s, f"{PUBLIC}/catalog/abc.jpg")
    assert not r2_client.is_ours(s, "https://covers.kitabi.in.evil.test/catalog/abc.jpg")
    assert not r2_client.is_ours(s, "https://covers.openlibrary.org/b/id/1-L.jpg")
    assert not r2_client.is_ours(s, None)
    assert not r2_client.is_ours(_settings(r2_covers_public_url=""), f"{PUBLIC}/catalog/abc.jpg")


def test_a_trailing_slash_on_the_public_url_does_not_double_up():
    s = _settings(r2_covers_public_url=f"{PUBLIC}/")
    assert r2_client.public_url(s, "catalog/abc.jpg") == f"{PUBLIC}/catalog/abc.jpg"


# --------------------------------------------------------------------------
# The upload
# --------------------------------------------------------------------------


async def test_an_upload_goes_to_the_bucket_endpoint_and_returns_the_public_url():
    seen = {}

    def handler(request):
        seen["method"] = request.method
        seen["url"] = str(request.url)
        seen["headers"] = request.headers
        seen["body"] = request.content
        return httpx.Response(200)

    async with _client(handler) as c:
        url = await r2_client.put_object(
            c, _settings(), "catalog/abc.jpg", b"jpeg-bytes", "image/jpeg"
        )

    assert url == f"{PUBLIC}/catalog/abc.jpg"
    assert seen["method"] == "PUT"
    assert seen["url"] == "https://acct123.r2.cloudflarestorage.com/kitabi-covers/catalog/abc.jpg"
    assert seen["body"] == b"jpeg-bytes"
    assert seen["headers"]["content-type"] == "image/jpeg"
    assert "immutable" in seen["headers"]["cache-control"]
    auth = seen["headers"]["authorization"]
    assert auth.startswith("AWS4-HMAC-SHA256 Credential=AKID/")
    assert "/auto/s3/aws4_request" in auth
    # Everything that decides how the object is served is covered by the
    # signature, not merely sent alongside it.
    assert "SignedHeaders=cache-control;content-type;host;x-amz-content-sha256;x-amz-date" in auth


async def test_a_refused_upload_returns_none_rather_than_a_url():
    """The caller must not point the catalogue at something that is not there."""
    async with _client(lambda r: httpx.Response(403, text="<Error/>")) as c:
        assert await r2_client.put_object(c, _settings(), "catalog/x.jpg", b"x", "image/jpeg") is (
            None
        )


async def test_a_network_failure_returns_none():
    def boom(request):
        raise httpx.ConnectError("no route")

    async with _client(boom) as c:
        assert await r2_client.put_object(c, _settings(), "catalog/x.jpg", b"x", "image/jpeg") is (
            None
        )
