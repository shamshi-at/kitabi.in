"""Put one object into Cloudflare R2, over its S3-compatible API.

R2 speaks S3, and S3 wants every request signed with AWS Signature Version 4.
That is the whole of this module: a signer and one `PUT`. It is hand-written
over `httpx` rather than pulled in with `boto3` for the same reason
`cover_storage` talks to Supabase Storage with a bare POST — the API makes one
kind of request to this service, and an 80 MB SDK with its own synchronous HTTP
stack is a lot of dependency for one verb.

`sign` is pure and takes the clock as an argument, so it is tested directly
against the worked example AWS publishes for exactly this request shape
(`tests/test_r2_client.py`). A signer that reproduces that signature is right;
one that does not fails there rather than as a 403 from production in the middle of the night.

**Dormant without all five `R2_*` settings** (rule 8): `configured` is false,
nothing here is called, and no request leaves the process.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import re
from datetime import UTC, datetime
from urllib.parse import quote

import httpx

from app.core.config import Settings, get_settings

logger = logging.getLogger(__name__)

#: R2 has no regions; its S3 endpoint expects this literal in the signature.
REGION = "auto"
SERVICE = "s3"
_ALGORITHM = "AWS4-HMAC-SHA256"


def configured(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    return bool(
        settings.r2_account_id
        and settings.r2_access_key_id
        and settings.r2_secret_access_key
        and settings.r2_covers_bucket
        and settings.r2_covers_public_url
    )


def public_base(settings: Settings) -> str | None:
    """The bucket's public origin with no trailing slash, or None when unset."""
    base = (settings.r2_covers_public_url or "").strip().rstrip("/")
    return base or None


def public_url(settings: Settings, key: str) -> str:
    return f"{public_base(settings)}/{key}"


def is_ours(settings: Settings, url: str | None) -> bool:
    """Already served from our R2 bucket.

    Asks only about the public origin, not the credentials: recognising our own
    cover must keep working on a deployment that can read the catalogue but was
    never given the keys to write to the bucket.
    """
    base = public_base(settings)
    return bool(url and base and url.startswith(f"{base}/"))


def _hmac(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode(), hashlib.sha256).digest()


def sign(
    *,
    method: str,
    host: str,
    path: str,
    headers: dict[str, str],
    payload_hash: str,
    access_key: str,
    secret_key: str,
    region: str,
    now: datetime,
) -> dict[str, str]:
    """The headers to send, `Authorization` included, for one S3 request.

    `headers` are the caller's own (content type, cache control…); every one of
    them is signed, along with `host` and the two `x-amz-*` headers added here.
    Signing more than S3 strictly requires is deliberate: an unsigned
    `Cache-Control` is one a hop in between could rewrite.

    `path` is the raw object path (`/bucket/key`); it is URI-encoded here, once,
    which is S3's rule and differs from every other AWS service's twice.
    """
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date = now.strftime("%Y%m%d")

    signed = {k.lower(): " ".join(v.split()) for k, v in headers.items()}
    signed["host"] = host
    signed["x-amz-content-sha256"] = payload_hash
    signed["x-amz-date"] = amz_date
    names = sorted(signed)

    canonical_request = "\n".join(
        [
            method,
            quote(path, safe="/-_.~"),
            "",  # no query string
            "".join(f"{name}:{signed[name]}\n" for name in names),
            ";".join(names),
            payload_hash,
        ]
    )
    scope = f"{date}/{region}/{SERVICE}/aws4_request"
    string_to_sign = "\n".join(
        [
            _ALGORITHM,
            amz_date,
            scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    key = _hmac(f"AWS4{secret_key}".encode(), date)
    for part in (region, SERVICE, "aws4_request"):
        key = _hmac(key, part)
    signature = hmac.new(key, string_to_sign.encode(), hashlib.sha256).hexdigest()

    out = {k: v for k, v in headers.items()}
    out["x-amz-content-sha256"] = payload_hash
    out["x-amz-date"] = amz_date
    out["Authorization"] = (
        f"{_ALGORITHM} Credential={access_key}/{scope}, "
        f"SignedHeaders={';'.join(names)}, Signature={signature}"
    )
    return out


async def put_object(
    client: httpx.AsyncClient,
    settings: Settings,
    key: str,
    body: bytes,
    content_type: str,
    *,
    now: datetime | None = None,
) -> str | None:
    """Upload `body` at `key` and return its public URL, or None on any failure.

    None rather than an exception: the caller must not point the catalogue at
    something that is not there, and "could not store it right now" is an
    ordinary outcome for it to handle, not a crash.

    A `PUT` to an existing key overwrites it, which is what makes the callers'
    content-addressed keys idempotent — the same bytes always land on the same
    object.
    """
    host = f"{settings.r2_account_id}.r2.cloudflarestorage.com"
    path = f"/{settings.r2_covers_bucket}/{key}"
    headers = sign(
        method="PUT",
        host=host,
        path=path,
        headers={
            "Content-Type": content_type,
            # The key is derived from the bytes, so different art is a
            # different URL and this object never changes in place.
            "Cache-Control": "public, max-age=31536000, immutable",
        },
        payload_hash=hashlib.sha256(body).hexdigest(),
        access_key=settings.r2_access_key_id,
        secret_key=settings.r2_secret_access_key,
        region=REGION,
        now=now or datetime.now(UTC),
    )
    try:
        resp = await client.put(
            f"https://{host}{quote(path, safe='/-_.~')}", content=body, headers=headers
        )
    except httpx.HTTPError as exc:
        logger.warning("r2: could not reach the bucket endpoint: %s", type(exc).__name__)
        return None
    if resp.status_code >= 400:
        # S3 says *why* in the body (`AccessDenied`, `SignatureDoesNotMatch`,
        # `NoSuchBucket`…), and those three have three different fixes. Without
        # this line a wrong key is indistinguishable from a busy night.
        code = re.search(r"<Code>([^<]{1,80})</Code>", resp.text or "")
        logger.warning(
            "r2: upload refused: HTTP %s %s", resp.status_code, code.group(1) if code else ""
        )
        return None
    return public_url(settings, key)
