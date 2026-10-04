"""The token check itself — real PyJWT, real keys, a real key-set endpoint.

Every other test either overrides `get_current_user` (the `client` fixture) or
patches `jwt.decode` away (`test_suspension.py`), so until this file the one
function that decides who a request is had no test of its own. That is how the
auth library sat on thirteen advisories with nothing here able to say which of
them reached us (found 4 Oct 2026, when `pip-audit` had been failing CI for a
day).

Nothing inside PyJWT is stubbed. The key set is served by a real HTTP server on
127.0.0.1, so the library's own fetch, cache and key-id lookup run as they do
in production — which is the only way to count how often it fetches. Three of
these tests fail on PyJWT 2.13.0 and are the reason for the pin in
`requirements.txt`:

- a forged token whose payload — or header — is deeply nested JSON raised
  `RecursionError`, which is not a `PyJWTError`, so it went past our `except`
  as a 500 — from anyone, with no valid signature (PYSEC-2026-4141 and -4142,
  fixed in 2.15.0 and 2.14.0);
- a token naming a key id we do not have made the API re-fetch the key set on
  *every* request — an outbound call per unauthenticated request, made
  synchronously inside the event loop (PYSEC-2026-4140, fixed in 2.14.0).

The rest pin what the upgrade must not change: a good token is accepted, and
every way of being a bad one is a 401.
"""

import base64
import http.server
import json
import threading
import time
import types
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from jwt.algorithms import ECAlgorithm

import app.core.security as sec
from app.services import fcm_client

AUDIENCE = "authenticated"
KID = "key-2026-10"


class _NoProfile:
    """The database, for a reader with no profile row: not suspended."""

    async def scalar(self, _stmt):  # noqa: ANN001, ANN202
        return None


def _jwk(private_key: ec.EllipticCurvePrivateKey, kid: str) -> dict:
    jwk = ECAlgorithm.to_jwk(private_key.public_key(), as_dict=True)
    return {**jwk, "kid": kid, "alg": "ES256", "use": "sig"}


@pytest.fixture
def issuer(monkeypatch):
    """A key-set endpoint on localhost, and `security` pointed at it.

    Yields a handle with the signing key, the issuer, how many times the
    endpoint has been fetched, and `publish()` to change what it serves.
    """
    key = ec.generate_private_key(ec.SECP256R1())
    state = {"keys": [_jwk(key, KID)], "hits": 0}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 — the stdlib's name
            state["hits"] += 1
            body = json.dumps({"keys": state["keys"]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):  # quiet
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    settings = types.SimpleNamespace(
        jwks_url=f"{base}/auth/v1/.well-known/jwks.json",
        jwt_issuer=f"{base}/auth/v1",
        jwt_audience=AUDIENCE,
    )
    monkeypatch.setattr(sec, "get_settings", lambda: settings)
    # The client is a module-level singleton; each test gets its own, with an
    # empty cache, pointed at this server.
    monkeypatch.setattr(sec, "_jwks_client", None)

    handle = types.SimpleNamespace(
        key=key,
        issuer=settings.jwt_issuer,
        hits=lambda: state["hits"],
        publish=lambda keys: state.update(keys=keys),
    )
    try:
        yield handle
    finally:
        server.shutdown()
        server.server_close()


def _claims(issuer, **over) -> dict:  # noqa: ANN001
    now = int(time.time())
    return {
        "sub": str(uuid.uuid4()),
        "aud": AUDIENCE,
        "iss": issuer.issuer,
        "iat": now,
        "exp": now + 3600,
        "email": "reader@example.com",
        "user_metadata": {"full_name": "Anaya", "picture": "https://example.com/a.jpg"},
        **over,
    }


def _sign(issuer, claims: dict, *, key=None, kid: str = KID) -> str:  # noqa: ANN001
    return jwt.encode(claims, key or issuer.key, algorithm="ES256", headers={"kid": kid})


async def _check(token: str) -> dict:
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    return await sec.get_current_user(creds, _NoProfile())


async def _rejected(token: str) -> None:
    """The token is refused as a 401 — not accepted, and not a crash."""
    with pytest.raises(HTTPException) as refused:
        await _check(token)
    assert refused.value.status_code == 401
    assert refused.value.detail["code"] == "unauthorized"


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


# --- a good token -------------------------------------------------------------


async def test_a_token_supabase_signed_is_accepted(issuer):
    claims = _claims(issuer)
    user = await _check(_sign(issuer, claims))
    assert user == {
        "id": claims["sub"],
        "email": "reader@example.com",
        "avatar_url": "https://example.com/a.jpg",
        "full_name": "Anaya",
    }


async def test_the_key_set_is_fetched_once_not_per_request(issuer):
    for _ in range(5):
        await _check(_sign(issuer, _claims(issuer)))
    assert issuer.hits() == 1


# --- every way of being a bad one is a 401 -------------------------------------


async def test_an_expired_token_is_refused(issuer):
    await _rejected(_sign(issuer, _claims(issuer, exp=int(time.time()) - 60)))


async def test_a_token_for_another_audience_is_refused(issuer):
    await _rejected(_sign(issuer, _claims(issuer, aud="service_role")))


async def test_a_token_from_another_issuer_is_refused(issuer):
    await _rejected(_sign(issuer, _claims(issuer, iss="https://evil.example/auth/v1")))


@pytest.mark.parametrize("claim", ["exp", "iss", "aud", "sub"])
async def test_a_token_missing_a_required_claim_is_refused(issuer, claim):
    claims = _claims(issuer)
    del claims[claim]
    await _rejected(_sign(issuer, claims))


async def test_a_token_signed_by_somebody_elses_key_is_refused(issuer):
    """It names our key id; the signature is what has to match."""
    stranger = ec.generate_private_key(ec.SECP256R1())
    await _rejected(_sign(issuer, _claims(issuer), key=stranger))


async def test_a_token_with_a_tampered_payload_is_refused(issuer):
    head, _payload, signature = _sign(issuer, _claims(issuer)).split(".")
    forged = _b64(json.dumps(_claims(issuer, email="owner@kitabi.in")).encode())
    await _rejected(f"{head}.{forged}.{signature}")


async def test_an_unsigned_token_is_refused(issuer):
    head = _b64(json.dumps({"alg": "none", "typ": "JWT", "kid": KID}).encode())
    payload = _b64(json.dumps(_claims(issuer)).encode())
    await _rejected(f"{head}.{payload}.")


@pytest.mark.parametrize("form", ["pem", "der", "jwk"])
async def test_the_public_key_cannot_be_used_as_a_shared_secret(issuer, form):
    """Algorithm confusion: the key set is public, so anyone can HMAC a token
    with the public key as the secret and label it HS256. Our allow-list has no
    HMAC algorithm in it; that, not the library's guard, is what refuses this —
    which is why most of the thirteen advisories never reached us."""
    public = issuer.key.public_key()
    secret = {
        "pem": public.public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
        ),
        "der": public.public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
        ),
        "jwk": json.dumps(_jwk(issuer.key, KID)).encode(),
    }[form]
    head = _b64(json.dumps({"alg": "HS256", "typ": "JWT", "kid": KID}).encode())
    payload = _b64(json.dumps(_claims(issuer)).encode())
    # Signed by hand: the library (rightly) refuses to *make* such a token.
    import hashlib  # noqa: PLC0415
    import hmac  # noqa: PLC0415

    mac = hmac.new(secret, f"{head}.{payload}".encode(), hashlib.sha256).digest()
    await _rejected(f"{head}.{payload}.{_b64(mac)}")


@pytest.mark.parametrize("token", ["", "tok", "a.b.c", "....", "é.é.é"])
async def test_something_that_is_not_a_token_is_refused(issuer, token):
    await _rejected(token)


async def test_a_deeply_nested_payload_is_refused_not_a_crash(issuer):
    """PYSEC-2026-4141. No signature needed: the payload is parsed to find the
    key id before anything is verified. On PyJWT 2.13.0 this raised
    `RecursionError` straight through `except jwt.PyJWTError` — a 500 on demand
    for anyone who can send a request."""
    head = _b64(json.dumps({"alg": "ES256", "typ": "JWT", "kid": KID}).encode())
    depth = 20_000
    payload = _b64(b"[" * depth + b"]" * depth)
    await _rejected(f"{head}.{payload}.AAAA")


async def test_a_deeply_nested_header_is_refused_not_a_crash(issuer):
    """PYSEC-2026-4142, the same crash one segment earlier. Its advisory says
    the token is too large to ride in an `Authorization` header; measured here
    on 2.13.0 it took 26 KB, which is not."""
    depth = 20_000
    head = _b64(
        b'{"alg":"ES256","kid":"' + KID.encode() + b'","x":' + b"[" * depth + b"]" * depth + b"}"
    )
    payload = _b64(json.dumps(_claims(issuer)).encode())
    await _rejected(f"{head}.{payload}.AAAA")


async def test_unknown_key_ids_do_not_make_us_fetch_the_key_set_every_time(issuer):
    """PYSEC-2026-4140. The key id is read from the unverified header, so
    anyone can name one we have never seen. On PyJWT 2.13.0 each such request
    re-fetched the key set — an outbound call to Supabase per unauthenticated
    request, blocking the event loop while it ran."""
    for n in range(25):
        await _rejected(_sign(issuer, _claims(issuer), kid=f"never-seen-{n}"))
    assert issuer.hits() <= 2, "one fetch, at most one forced refresh — not one per request"


# --- and the fix for that must not break key rotation ---------------------------


async def test_a_rotated_key_is_picked_up(issuer, monkeypatch):
    """Supabase rotates its signing key: a new key id appears in the key set
    and tokens start arriving signed with it. The guard against the storm above
    is a cooldown between forced refreshes (30s by default), so the new key is
    found on the first token after it — not never."""
    await _check(_sign(issuer, _claims(issuer)))  # the key set is now cached

    rotated = ec.generate_private_key(ec.SECP256R1())
    issuer.publish([_jwk(issuer.key, KID), _jwk(rotated, "key-2026-11")])
    token = _sign(issuer, _claims(issuer), key=rotated, kid="key-2026-11")

    # A minute later. Only the key client's clock is moved — the event loop
    # keeps its own. (`raising=False`: 2.13.0 had no cooldown and no clock.)
    real = time.monotonic
    later = types.SimpleNamespace(monotonic=lambda: real() + 60)
    monkeypatch.setattr(jwt.jwks_client, "time", later, raising=False)

    user = await _check(token)
    assert user["email"] == "reader@example.com"
    assert issuer.hits() == 2


async def test_a_retired_key_stops_working_once_the_key_set_is_refetched(issuer):
    """The other half of rotation: a token signed by a key that is no longer
    published is refused by a process that starts after the key was retired."""
    token = _sign(issuer, _claims(issuer))
    issuer.publish([_jwk(ec.generate_private_key(ec.SECP256R1()), "key-2026-11")])
    await _rejected(token)


# --- the other thing PyJWT does here: sign the push-notification grant ----------


async def test_the_push_grant_is_still_signed_the_way_google_verifies_it(monkeypatch):
    """`fcm_client` mints an RS256 assertion with the service account's PEM
    key. It is the only place we *encode*, and it had no test either."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    creds = {"client_email": "push@kitabi.iam.gserviceaccount.com", "private_key": pem}
    monkeypatch.setattr(fcm_client, "_creds", creds)
    monkeypatch.setattr(fcm_client, "_token_cache", {"value": None, "exp": 0.0})
    sent = {}

    class Google:
        async def post(self, url, data):  # noqa: ANN001, ANN202
            sent.update(url=url, **data)
            return types.SimpleNamespace(
                raise_for_status=lambda: None,
                json=lambda: {"access_token": "ya29.test", "expires_in": 3600},
            )

    assert await fcm_client._access_token(Google()) == "ya29.test"
    assert sent["grant_type"] == "urn:ietf:params:oauth:grant-type:jwt-bearer"
    claims = jwt.decode(
        sent["assertion"], key.public_key(), algorithms=["RS256"], audience=sent["url"]
    )
    assert claims["iss"] == claims["sub"] == creds["client_email"]
    assert claims["scope"] == "https://www.googleapis.com/auth/firebase.messaging"
    assert claims["exp"] - claims["iat"] == 3600
