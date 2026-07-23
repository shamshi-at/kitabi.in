"""An admin changing their own password from inside the console. Requires the
current password (re-auth), enforces the same minimum as the seed, and audits
the change. This is also the page a forced post-reset change will land on."""

from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .. import config, queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..flash import pop_flash, set_flash
from ..templating import templates

router = APIRouter(prefix="/account")


@router.get("/password")
async def password_form(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "account_password.html",
        {
            "admin": admin,
            "active": None,
            "badges": badges,
            "flash": flash,
            "minlen": config.MIN_PASSWORD_LENGTH,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/password")
async def change_password(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    current: Annotated[str, Form()],
    new_password: Annotated[str, Form()],
    confirm: Annotated[str, Form()],
) -> RedirectResponse:
    resp = RedirectResponse("/account/password", status_code=303)
    if not security.verify_password(current, admin.password_hash):
        await security.audit(
            db,
            "password.change_failed",
            admin_id=admin.id,
            summary="wrong current password",
            ip=client_ip(request),
        )
        set_flash(resp, "err", "Your current password is incorrect.")
        return resp
    if len(new_password) < config.MIN_PASSWORD_LENGTH:
        set_flash(
            resp, "err", f"New password must be at least {config.MIN_PASSWORD_LENGTH} characters."
        )
        return resp
    if new_password != confirm:
        set_flash(resp, "err", "The new passwords don't match.")
        return resp
    if new_password == current:
        set_flash(resp, "err", "The new password must differ from the current one.")
        return resp
    admin.password_hash = security.hash_password(new_password)
    await db.commit()
    await security.audit(db, "password.change", admin_id=admin.id, ip=client_ip(request))
    set_flash(resp, "ok", "Password changed.")
    return resp
