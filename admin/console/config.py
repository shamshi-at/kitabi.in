"""Admin-app settings. Reuses the API's database via app.core.config; adds only
the admin-specific knobs (session lifetime, lockout, cookie name)."""

import os

# Session cookie. httpOnly + SameSite=Strict + Secure in production. The value
# is an opaque token; the session lives in the DB (admin_sessions).
COOKIE_NAME = "kitabi_admin"
# Absolute session lifetime — a back-office session should not live for days.
SESSION_TTL_HOURS = 12

# Brute-force guard: this many failures locks the account for LOCKOUT_MINUTES.
MAX_FAILED_ATTEMPTS = 5
LOCKOUT_MINUTES = 15

# Minimum admin password length. Kept modest (owner decision, 24 Jul 2026)
# because mandatory TOTP + the 5-attempt lockout carry the real weight; the
# password alone never grants access.
MIN_PASSWORD_LENGTH = 8

# TOTP + recovery.
TOTP_ISSUER = "Kitabi Admin"
RECOVERY_CODE_COUNT = 8

# Argon2id parameters — sane, not paranoid (this is a handful of operators).
ARGON2_TIME_COST = 3
ARGON2_MEMORY_KIB = 64 * 1024
ARGON2_PARALLELISM = 2


def is_production() -> bool:
    # The API sets ENV=production on Railway; reuse the same signal so the
    # Secure cookie flag flips on in the deployed console.
    return os.getenv("ENV", os.getenv("env", "dev")).lower() == "production"
