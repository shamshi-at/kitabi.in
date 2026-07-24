"""Admin user management — super-admin only. Create an admin with an initial
password (shared out of band; they enrol TOTP on first sign-in), change a role,
or revoke access. Three self-protections make the last super admin impossible
to lock out: no self-revoke, no self-demote, and the final super admin cannot
be removed or downgraded by anyone.
"""

import uuid

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, select

from .. import emails, mail, queries, security
from ..deps import DbSession, RequireSuperAdmin, client_ip
from ..flash import pop_flash as _pop_flash
from ..flash import set_flash as _flash
from ..models_ref import ADMIN_ROLES, ROLE_SUPER_ADMIN, TOKEN_INVITE, AdminUser
from ..templating import templates

router = APIRouter(prefix="/admins")


async def _super_admin_count(db: DbSession) -> int:
    return int(
        await db.scalar(
            select(func.count())
            .select_from(AdminUser)
            .where(AdminUser.role == ROLE_SUPER_ADMIN, AdminUser.is_active.is_(True))
        )
        or 0
    )


@router.get("")
async def list_admins(request: Request, admin: RequireSuperAdmin, db: DbSession) -> HTMLResponse:
    rows = (
        (await db.execute(select(AdminUser).order_by(AdminUser.created_at.asc()))).scalars().all()
    )
    badges = await queries.nav_badges(db)
    flash = _pop_flash(request)
    invited = _pop_invited(request)
    resp = templates.TemplateResponse(
        request,
        "admins.html",
        {
            "admin": admin,
            "active": "admins",
            "badges": badges,
            "admins": rows,
            "roles": ADMIN_ROLES,
            "invited": invited,
            "flash": flash,
        },
    )
    # One-shot: clear so a refresh doesn't re-show the flash or the invite link.
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    if invited:
        resp.delete_cookie("admin_invite", path="/")
    return resp


def _pop_invited(request: Request) -> dict | None:
    raw = request.cookies.get("admin_invite")
    if not raw:
        return None
    email, _, link = raw.partition("|")
    return {"email": email, "link": link}


@router.post("/create")
async def create_admin(
    request: Request,
    admin: RequireSuperAdmin,
    db: DbSession,
    email: str = Form(...),
    role: str = Form(...),
) -> RedirectResponse:
    resp = RedirectResponse("/admins", status_code=303)
    email = email.strip().lower()
    if role not in ADMIN_ROLES:
        _flash(resp, "err", "Unknown role.")
        return resp
    exists = (
        await db.execute(select(AdminUser).where(AdminUser.email == email))
    ).scalar_one_or_none()
    if exists is not None:
        _flash(resp, "err", "An admin with that email already exists.")
        return resp

    # Create the row with an unusable random password — the invitee sets their
    # own via the emailed link (they can't sign in until they do).
    import secrets

    new = AdminUser(
        email=email,
        password_hash=security.hash_password(secrets.token_urlsafe(24)),
        role=role,
        created_by_admin_id=admin.id,
    )
    db.add(new)
    await db.commit()

    token = security.new_url_token()
    await security.create_auth_token(db, new.id, TOKEN_INVITE, token, ttl_minutes=48 * 60)
    link = f"{mail.base_url()}/invite/{token}"
    subject, text, html = emails.invite_email(link, role)
    mail.send(email, subject, text, html=html)
    await security.audit(
        db,
        "admin.invite",
        admin_id=admin.id,
        target_type="admin",
        target_id=str(new.id),
        summary=f"{email} as {role}",
        ip=client_ip(request),
    )

    if mail.is_configured():
        _flash(resp, "ok", f"Invitation emailed to {email}.")
    else:
        # No mail transport yet — surface the link so the super admin can share
        # it out of band (and it's also in the server log).
        resp.set_cookie(
            "admin_invite",
            f"{email}|{link}",
            max_age=60,
            httponly=True,
            samesite="strict",
            path="/",
        )
        _flash(resp, "ok", "Admin invited. Email isn't configured — copy the setup link below.")
    return resp


@router.post("/{admin_id}/role")
async def change_role(
    request: Request,
    admin: RequireSuperAdmin,
    db: DbSession,
    admin_id: uuid.UUID,
    role: str = Form(...),
) -> RedirectResponse:
    resp = RedirectResponse("/admins", status_code=303)
    target = await db.get(AdminUser, admin_id)
    if target is None or role not in ADMIN_ROLES:
        _flash(resp, "err", "No such admin or role.")
        return resp
    if target.id == admin.id and role != ROLE_SUPER_ADMIN:
        _flash(resp, "err", "You cannot demote yourself.")
        return resp
    if (
        target.role == ROLE_SUPER_ADMIN
        and role != ROLE_SUPER_ADMIN
        and await _super_admin_count(db) <= 1
    ):
        _flash(resp, "err", "This is the last super admin — promote someone else first.")
        return resp
    old = target.role
    target.role = role
    await db.commit()
    await security.audit(
        db,
        "admin.role",
        admin_id=admin.id,
        target_type="admin",
        target_id=str(target.id),
        summary=f"{old} → {role}",
        ip=client_ip(request),
    )
    _flash(resp, "ok", f"Role updated to {role.replace('_', ' ')}.")
    return resp


@router.post("/{admin_id}/revoke")
async def revoke_admin(
    request: Request, admin: RequireSuperAdmin, db: DbSession, admin_id: uuid.UUID
) -> RedirectResponse:
    resp = RedirectResponse("/admins", status_code=303)
    target = await db.get(AdminUser, admin_id)
    if target is None:
        _flash(resp, "err", "No such admin.")
        return resp
    if target.id == admin.id:
        _flash(resp, "err", "You cannot revoke your own access.")
        return resp
    if target.role == ROLE_SUPER_ADMIN and await _super_admin_count(db) <= 1:
        _flash(resp, "err", "This is the last super admin and cannot be revoked.")
        return resp
    target.is_active = False
    await db.commit()
    # Kill any live sessions for the revoked admin.
    from datetime import UTC, datetime

    from ..models_ref import AdminSession

    sessions = (
        (await db.execute(select(AdminSession).where(AdminSession.admin_id == target.id)))
        .scalars()
        .all()
    )
    for s in sessions:
        if s.revoked_at is None:
            s.revoked_at = datetime.now(UTC)
    await db.commit()
    await security.audit(
        db,
        "admin.revoke",
        admin_id=admin.id,
        target_type="admin",
        target_id=str(target.id),
        summary=target.email,
        ip=client_ip(request),
    )
    _flash(resp, "ok", "Access revoked and sessions ended.")
    return resp
