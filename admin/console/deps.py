"""FastAPI dependencies: the request-scoped DB session (reusing the API's engine)
and the signed-in admin resolved from the session cookie, with role gates."""

from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from . import config, security
from .models_ref import ROLE_EDITOR, ROLE_SUPER_ADMIN, AdminUser, SessionLocal


async def get_db() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session


DbSession = Annotated[AsyncSession, Depends(get_db)]


class RedirectException(Exception):
    """Raised by a dependency to bounce an unauthenticated/unauthorised request.
    Turned into a 303 by the handler in main.py (dependencies can't return a
    response directly)."""

    def __init__(self, location: str):
        self.location = location


def client_ip(request: Request) -> str | None:
    # Railway/Cloudflare sit in front, so trust the forwarded header first.
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else None


async def _resolve_admin(request: Request, db: AsyncSession) -> AdminUser:
    """The signed-in, TOTP-enrolled admin, or a redirect to the right gate."""
    token = request.cookies.get(config.COOKIE_NAME)
    admin = await security.session_admin(db, token)
    if admin is None:
        raise RedirectException("/sign-in")
    if admin.totp_enrolled_at is None:
        raise RedirectException("/enrol")
    return admin


async def current_admin(request: Request, db: DbSession) -> AdminUser:
    """The admin for a normal page. An admin flagged must_change_password (they
    signed in with a forgot-password OTP) is forced to set a real password
    before reaching anything else."""
    admin = await _resolve_admin(request, db)
    if admin.must_change_password:
        raise RedirectException("/account/force-password")
    return admin


async def current_admin_changing(request: Request, db: DbSession) -> AdminUser:
    """Like current_admin but WITHOUT the must_change redirect — for the
    force-password page itself, so it doesn't bounce to itself in a loop."""
    return await _resolve_admin(request, db)


CurrentAdmin = Annotated[AdminUser, Depends(current_admin)]
CurrentAdminChanging = Annotated[AdminUser, Depends(current_admin_changing)]

# Role ranking for the "at least this role" gates.
_RANK = {"moderator": 0, ROLE_EDITOR: 1, ROLE_SUPER_ADMIN: 2}


def require_role(minimum: str):
    """Dependency factory: admin must hold at least `minimum`."""

    async def _dep(admin: CurrentAdmin) -> AdminUser:
        if _RANK.get(admin.role, -1) < _RANK[minimum]:
            raise RedirectException("/?denied=1")
        return admin

    return _dep


RequireEditor = Annotated[AdminUser, Depends(require_role(ROLE_EDITOR))]
RequireSuperAdmin = Annotated[AdminUser, Depends(require_role(ROLE_SUPER_ADMIN))]
