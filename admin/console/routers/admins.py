"""Admin user management — super-admin only. Invite an admin (they set their own
password from an emailed link and enrol TOTP on first sign-in), resend an invite
that hasn't been accepted, change a role, or revoke access. Three
self-protections make the last super admin impossible to lock out: no
self-revoke, no self-demote, and the final super admin cannot be removed or
downgraded by anyone.
"""

import uuid

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, select

from .. import emails, mail, queries, security
from ..deps import DbSession, RequireSuperAdmin, client_ip
from ..flash import pop_flash as _pop_flash
from ..flash import set_flash as _flash
from ..models_ref import (
    ADMIN_ROLES,
    ROLE_SUPER_ADMIN,
    TOKEN_INVITE,
    AdminAuditLog,
    AdminUser,
)
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


async def _invite_pending(db: DbSession, rows) -> set:
    """Ids of the admins still waiting on their invite: active, never signed in,
    and no `admin.invite_accepted` in the trail. The trail is the one record of
    acceptance — the token's `used_at` can't say, because minting a new invite
    stamps the old one used too. The seeded founder has signed in, so never
    counts."""
    candidates = [a.id for a in rows if a.is_active and a.last_sign_in_at is None]
    if not candidates:
        return set()
    accepted = set(
        (
            await db.execute(
                select(AdminAuditLog.admin_id).where(
                    AdminAuditLog.action == "admin.invite_accepted",
                    AdminAuditLog.admin_id.in_(candidates),
                )
            )
        )
        .scalars()
        .all()
    )
    return {i for i in candidates if i not in accepted}


async def _send_invite(
    request: Request, resp: RedirectResponse, db: DbSession, admin: AdminUser, target: AdminUser
) -> None:
    """Mint a fresh 48h setup link for `target` and email it. Minting voids any
    earlier unused link, so only the newest one works. Without a mail transport
    the link is surfaced once on the next page instead."""
    token = security.new_url_token()
    await security.create_auth_token(db, target.id, TOKEN_INVITE, token, ttl_minutes=48 * 60)
    link = f"{mail.base_url()}/invite/{token}"
    subject, text, html = emails.invite_email(link, target.role)
    mail.send(target.email, subject, text, html=html)
    if not mail.is_configured():
        # No mail transport yet — surface the link so the super admin can share
        # it out of band (and it's also in the server log).
        resp.set_cookie(
            "admin_invite",
            f"{target.email}|{link}",
            max_age=60,
            httponly=True,
            samesite="strict",
            path="/",
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
            "pending": await _invite_pending(db, rows),
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

    await _send_invite(request, resp, db, admin, new)
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
        _flash(resp, "ok", "Admin invited. Email isn't configured — copy the setup link below.")
    return resp


@router.post("/{admin_id}/resend-invite")
async def resend_invite(
    request: Request, admin: RequireSuperAdmin, db: DbSession, admin_id: uuid.UUID
) -> RedirectResponse:
    """Send a pending admin a fresh setup link — the first expired, went to spam,
    or was lost. Refused once the invite has been accepted: a setup link sets
    the password, so on an accepted account it would be a way for one admin to
    take over another's."""
    resp = RedirectResponse("/admins", status_code=303)
    target = await db.get(AdminUser, admin_id)
    if target is None:
        _flash(resp, "err", "No such admin.")
        return resp
    if target.id not in await _invite_pending(db, [target]):
        _flash(resp, "err", f"{target.email} has already accepted their invite.")
        return resp
    await _send_invite(request, resp, db, admin, target)
    await security.audit(
        db,
        "admin.invite_resend",
        admin_id=admin.id,
        target_type="admin",
        target_id=str(target.id),
        summary=f"{target.email} as {target.role}",
        ip=client_ip(request),
    )
    if mail.is_configured():
        _flash(
            resp,
            "ok",
            f"A new invitation was emailed to {target.email}. The old link no longer works.",
        )
    else:
        _flash(resp, "ok", "New setup link made — the old one no longer works. Copy it below.")
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
