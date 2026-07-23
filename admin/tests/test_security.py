"""Unit tests for the admin auth primitives — the parts that must be exactly
right and don't need a database. The DB-backed flows (sign-in → TOTP → session,
claim approve, admin management) were verified end-to-end on a live server and
the dev DB; these lock in the cryptographic logic underneath them.
"""

import sys
from pathlib import Path

# Make the console package importable the way the app does.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pyotp

from console import security
from console.routers import auth as auth_router


def test_password_hash_roundtrip_and_rejection():
    h = security.hash_password("correct horse battery staple")
    assert h != "correct horse battery staple"  # never plaintext
    assert security.verify_password("correct horse battery staple", h)
    assert not security.verify_password("wrong", h)


def test_verify_password_never_raises_on_garbage_hash():
    # A malformed stored hash must read as "wrong", not 500 the sign-in.
    assert security.verify_password("anything", "not-a-real-argon2-hash") is False


def test_totp_accepts_current_code_and_rejects_stale():
    secret = security.new_totp_secret()
    now = pyotp.TOTP(secret).now()
    assert security.verify_totp(secret, now)
    assert security.verify_totp(secret, f" {now} ")  # tolerant of spacing
    assert not security.verify_totp(secret, "000000")


def test_totp_uri_names_the_issuer():
    uri = security.totp_uri(security.new_totp_secret(), "a@b.com")
    assert uri.startswith("otpauth://totp/")
    assert "Kitabi%20Admin" in uri or "Kitabi Admin" in uri


def test_recovery_codes_are_unique_and_shaped():
    codes = security.generate_recovery_codes()
    assert len(codes) == security.config.RECOVERY_CODE_COUNT
    assert len(set(codes)) == len(codes)
    for c in codes:
        a, _, b = c.partition("-")
        assert len(a) == 4 and len(b) == 4  # 4f2a-91cd


def test_pending_ticket_roundtrips_and_rejects_tampering():
    token = auth_router._sign_pending("abc-123")
    assert auth_router._read_pending(token) == "abc-123"
    # Flip the last character of the signature → rejected.
    bad = token[:-1] + ("0" if token[-1] != "0" else "1")
    assert auth_router._read_pending(bad) is None
    assert auth_router._read_pending(None) is None
    assert auth_router._read_pending("nope") is None


def test_pending_ticket_expires():
    import time

    real = time.time
    try:
        token = auth_router._sign_pending("who")
        # Jump past the TTL.
        time.time = lambda: real() + auth_router._PENDING_TTL + 5
        assert auth_router._read_pending(token) is None
    finally:
        time.time = real


def test_reset_otp_is_six_digits():
    for _ in range(20):
        otp = security.new_otp()
        assert len(otp) == 6 and otp.isdigit()


def test_url_tokens_are_long_and_unique():
    toks = {security.new_url_token() for _ in range(50)}
    assert len(toks) == 50
    assert all(len(t) >= 32 for t in toks)


def test_role_ranking_orders_least_to_most():
    from console.deps import _RANK
    from console.models_ref import ROLE_EDITOR, ROLE_MODERATOR, ROLE_SUPER_ADMIN

    assert _RANK[ROLE_MODERATOR] < _RANK[ROLE_EDITOR] < _RANK[ROLE_SUPER_ADMIN]
