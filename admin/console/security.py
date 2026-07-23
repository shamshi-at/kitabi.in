"""Admin auth primitives: Argon2id passwords, TOTP, recovery codes, opaque
DB-backed sessions, lockout, and the audit trail. No secret ever leaves here in
plaintext beyond the single moment a recovery code or TOTP secret is shown to
its owner.
"""

import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from . import config
from .models_ref import AdminAuditLog, AdminRecoveryCode, AdminSession, AdminUser

_ph = PasswordHasher(
    time_cost=config.ARGON2_TIME_COST,
    memory_cost=config.ARGON2_MEMORY_KIB,
    parallelism=config.ARGON2_PARALLELISM,
)


# ---- passwords -----------------------------------------------------------
def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    try:
        return _ph.verify(hashed, password)
    except VerifyMismatchError:
        return False
    except Exception:  # noqa: BLE001 — a malformed hash must read as "wrong", never 500
        return False


# ---- TOTP ----------------------------------------------------------------
def new_totp_secret() -> str:
    return pyotp.random_base32()


def totp_uri(secret: str, email: str) -> str:
    """otpauth:// URI to render as the enrolment QR."""
    return pyotp.TOTP(secret).provisioning_uri(name=email, issuer_name=config.TOTP_ISSUER)


def verify_totp(secret: str, code: str) -> bool:
    # valid_window=1 tolerates ±30s of clock drift; a used code is refused for
    # its window by the sign-in flow marking last_sign_in_at.
    return pyotp.TOTP(secret).verify(code.strip().replace(" ", ""), valid_window=1)


# ---- recovery codes ------------------------------------------------------
def _hash_token(token: str) -> str:
    # Recovery codes and session tokens are high-entropy already, so a plain
    # SHA-256 is the right hash — argon2 is for low-entropy passwords.
    return hashlib.sha256(token.encode()).hexdigest()


def generate_recovery_codes(n: int = config.RECOVERY_CODE_COUNT) -> list[str]:
    # Format 4f2a-91cd — short, unambiguous, single-use.
    return [f"{secrets.token_hex(2)}-{secrets.token_hex(2)}" for _ in range(n)]


async def consume_recovery_code(db: AsyncSession, admin_id, code: str) -> bool:
    """Spend a matching unused recovery code. Constant-time compare over hashes."""
    target = _hash_token(code.strip().lower())
    rows = (
        (
            await db.execute(
                select(AdminRecoveryCode).where(
                    AdminRecoveryCode.admin_id == admin_id,
                    AdminRecoveryCode.used_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    for row in rows:
        if hmac.compare_digest(row.code_hash, target):
            row.used_at = datetime.now(UTC)
            await db.commit()
            return True
    return False


async def store_recovery_codes(db: AsyncSession, admin_id, codes: list[str]) -> None:
    # Replace any prior set (re-enrolment invalidates old codes).
    existing = (
        (await db.execute(select(AdminRecoveryCode).where(AdminRecoveryCode.admin_id == admin_id)))
        .scalars()
        .all()
    )
    for row in existing:
        await db.delete(row)
    for code in codes:
        db.add(AdminRecoveryCode(admin_id=admin_id, code_hash=_hash_token(code.lower())))
    await db.commit()


# ---- sessions ------------------------------------------------------------
async def create_session(db: AsyncSession, admin_id, ip: str | None, ua: str | None) -> str:
    """Mint a session; return the opaque token to put in the cookie (only its
    hash is stored)."""
    token = secrets.token_urlsafe(32)
    db.add(
        AdminSession(
            admin_id=admin_id,
            token_hash=_hash_token(token),
            expires_at=datetime.now(UTC) + timedelta(hours=config.SESSION_TTL_HOURS),
            ip=ip,
            user_agent=(ua or "")[:400] or None,
        )
    )
    await db.commit()
    return token


async def session_admin(db: AsyncSession, token: str | None) -> AdminUser | None:
    """The active admin for a cookie token, or None. Expired/revoked → None."""
    if not token:
        return None
    row = (
        await db.execute(select(AdminSession).where(AdminSession.token_hash == _hash_token(token)))
    ).scalar_one_or_none()
    if row is None or row.revoked_at is not None:
        return None
    if row.expires_at <= datetime.now(UTC):
        return None
    admin = await db.get(AdminUser, row.admin_id)
    if admin is None or not admin.is_active:
        return None
    return admin


async def revoke_session(db: AsyncSession, token: str | None) -> None:
    if not token:
        return
    row = (
        await db.execute(select(AdminSession).where(AdminSession.token_hash == _hash_token(token)))
    ).scalar_one_or_none()
    if row is not None and row.revoked_at is None:
        row.revoked_at = datetime.now(UTC)
        await db.commit()


# ---- lockout -------------------------------------------------------------
def is_locked(admin: AdminUser) -> bool:
    return admin.locked_until is not None and admin.locked_until > datetime.now(UTC)


async def register_failure(db: AsyncSession, admin: AdminUser) -> None:
    admin.failed_attempts += 1
    if admin.failed_attempts >= config.MAX_FAILED_ATTEMPTS:
        admin.locked_until = datetime.now(UTC) + timedelta(minutes=config.LOCKOUT_MINUTES)
        admin.failed_attempts = 0
    await db.commit()


async def register_success(db: AsyncSession, admin: AdminUser) -> None:
    admin.failed_attempts = 0
    admin.locked_until = None
    admin.last_sign_in_at = datetime.now(UTC)
    await db.commit()


# ---- audit ---------------------------------------------------------------
async def audit(
    db: AsyncSession,
    action: str,
    *,
    admin_id=None,
    target_type: str | None = None,
    target_id: str | None = None,
    summary: str | None = None,
    ip: str | None = None,
) -> None:
    """Append one line to the trail. Never raises into the caller — a failed
    audit write must not sink the action, but it commits on its own so a later
    rollback in the request can't erase it."""
    try:
        db.add(
            AdminAuditLog(
                admin_id=admin_id,
                action=action,
                target_type=target_type,
                target_id=str(target_id) if target_id is not None else None,
                summary=summary,
                ip=ip,
            )
        )
        await db.commit()
    except Exception:  # noqa: BLE001
        await db.rollback()
