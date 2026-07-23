"""Sign-in → password → TOTP → session, plus first-run TOTP enrolment and
recovery-code sign-in. The password step never mints a session on its own; a
session exists only after the second factor is satisfied.

Between the password and the 2FA step the identity is carried in a short-lived,
signed, httpOnly "pending" cookie holding just the admin id — no session, no
privileges, and it is cleared the moment 2FA succeeds or the flow is abandoned.
"""

import base64
import hashlib
import hmac
import json
import time

import segno
from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .. import config, security
from ..deps import DbSession, client_ip
from ..models_ref import AdminUser
from ..templating import templates

router = APIRouter()

PENDING_COOKIE = "kitabi_admin_pending"
_PENDING_TTL = 300  # 5 minutes to complete 2FA


# ---- the "password verified, 2FA pending" ticket -------------------------
def _pending_secret() -> bytes:
    # Derived from the DB URL — a stable per-deployment secret with no new env
    # var to manage. The ticket only names an admin id for five minutes and
    # confers nothing on its own, so this is sufficient.
    from app.core.config import get_settings

    return hashlib.sha256(("pending:" + get_settings().database_url).encode()).digest()


def _sign_pending(admin_id: str) -> str:
    body = json.dumps({"id": admin_id, "exp": int(time.time()) + _PENDING_TTL}).encode()
    b = base64.urlsafe_b64encode(body).decode()
    sig = hmac.new(_pending_secret(), b.encode(), hashlib.sha256).hexdigest()[:32]
    return f"{b}.{sig}"


def _read_pending(token: str | None) -> str | None:
    if not token or "." not in token:
        return None
    b, sig = token.rsplit(".", 1)
    good = hmac.new(_pending_secret(), b.encode(), hashlib.sha256).hexdigest()[:32]
    if not hmac.compare_digest(sig, good):
        return None
    try:
        data = json.loads(base64.urlsafe_b64decode(b))
    except Exception:  # noqa: BLE001
        return None
    if data.get("exp", 0) < int(time.time()):
        return None
    return data.get("id")


def _cookie_kwargs() -> dict:
    return {
        "httponly": True,
        "samesite": "strict",
        "secure": config.is_production(),
        "path": "/",
    }


def _render(request: Request, name: str, **ctx) -> HTMLResponse:
    return templates.TemplateResponse(request, name, ctx)


# ---- step 1: email + password -------------------------------------------
@router.get("/sign-in")
async def sign_in_form(request: Request, db: DbSession) -> HTMLResponse:
    # Already fully signed in? Go home.
    if await security.session_admin(db, request.cookies.get(config.COOKIE_NAME)):
        return RedirectResponse("/", status_code=303)
    return _render(request, "sign_in.html")


@router.post("/sign-in")
async def sign_in(
    request: Request, db: DbSession, email: str = Form(...), password: str = Form(...)
) -> HTMLResponse:
    ip = client_ip(request)
    email = email.strip().lower()
    from sqlalchemy import select

    admin = (
        await db.execute(select(AdminUser).where(AdminUser.email == email))
    ).scalar_one_or_none()

    # Uniform failure: never reveal whether the email exists.
    def deny(text="Incorrect email or password."):
        return _render(
            request, "sign_in.html", email=email, flash={"kind": "err", "text": text}
        )

    if admin is None or not admin.is_active:
        await security.audit(
            db,
            "auth.fail",
            target_type="email",
            target_id=email,
            summary="unknown or inactive",
            ip=ip,
        )
        return deny()
    if security.is_locked(admin):
        await security.audit(
            db, "auth.fail", admin_id=admin.id, summary="locked out", ip=ip
        )
        return deny("Account temporarily locked. Try again later.")
    if not security.verify_password(password, admin.password_hash):
        await security.register_failure(db, admin)
        await security.audit(
            db, "auth.fail", admin_id=admin.id, summary="bad password", ip=ip
        )
        return deny()

    # Password OK. Issue the pending ticket; the session is still not created.
    resp = RedirectResponse(
        "/enrol" if admin.totp_enrolled_at is None else "/sign-in/2fa", status_code=303
    )
    resp.set_cookie(
        PENDING_COOKIE,
        _sign_pending(str(admin.id)),
        max_age=_PENDING_TTL,
        **_cookie_kwargs(),
    )
    return resp


# ---- step 2: TOTP --------------------------------------------------------
@router.get("/sign-in/2fa")
async def twofa_form(request: Request) -> HTMLResponse:
    if _read_pending(request.cookies.get(PENDING_COOKIE)) is None:
        return RedirectResponse("/sign-in", status_code=303)
    return _render(request, "two_factor.html")


async def _complete_sign_in(
    request: Request, db: DbSession, admin: AdminUser
) -> RedirectResponse:
    ip = client_ip(request)
    await security.register_success(db, admin)
    token = await security.create_session(
        db, admin.id, ip, request.headers.get("user-agent")
    )
    await security.audit(db, "auth.success", admin_id=admin.id, ip=ip)
    resp = RedirectResponse("/", status_code=303)
    resp.set_cookie(
        config.COOKIE_NAME,
        token,
        max_age=config.SESSION_TTL_HOURS * 3600,
        **_cookie_kwargs(),
    )
    resp.delete_cookie(PENDING_COOKIE, path="/")
    return resp


@router.post("/sign-in/2fa")
async def twofa(request: Request, db: DbSession, code: str = Form(...)) -> HTMLResponse:
    admin_id = _read_pending(request.cookies.get(PENDING_COOKIE))
    if admin_id is None:
        return RedirectResponse("/sign-in", status_code=303)
    admin = await db.get(AdminUser, admin_id)
    if admin is None or admin.totp_secret is None or admin.totp_enrolled_at is None:
        return RedirectResponse("/sign-in", status_code=303)
    if not security.verify_totp(admin.totp_secret, code):
        await security.audit(
            db,
            "auth.fail",
            admin_id=admin.id,
            summary="bad totp",
            ip=client_ip(request),
        )
        return _render(
            request,
            "two_factor.html",
            flash={
                "kind": "err",
                "text": "That code didn't match. Try the current one.",
            },
        )
    return await _complete_sign_in(request, db, admin)


# ---- step 2 (alt): recovery code ----------------------------------------
@router.get("/sign-in/recovery")
async def recovery_form(request: Request) -> HTMLResponse:
    if _read_pending(request.cookies.get(PENDING_COOKIE)) is None:
        return RedirectResponse("/sign-in", status_code=303)
    return _render(request, "recovery.html")


@router.post("/sign-in/recovery")
async def recovery(
    request: Request, db: DbSession, code: str = Form(...)
) -> HTMLResponse:
    admin_id = _read_pending(request.cookies.get(PENDING_COOKIE))
    if admin_id is None:
        return RedirectResponse("/sign-in", status_code=303)
    admin = await db.get(AdminUser, admin_id)
    if admin is None or admin.totp_enrolled_at is None:
        return RedirectResponse("/sign-in", status_code=303)
    if not await security.consume_recovery_code(db, admin.id, code):
        await security.audit(
            db,
            "auth.fail",
            admin_id=admin.id,
            summary="bad recovery code",
            ip=client_ip(request),
        )
        return _render(
            request,
            "recovery.html",
            flash={"kind": "err", "text": "That code is not valid or already used."},
        )
    await security.audit(
        db, "auth.recovery_used", admin_id=admin.id, ip=client_ip(request)
    )
    return await _complete_sign_in(request, db, admin)


# ---- first-run enrolment -------------------------------------------------
def _grouped(secret: str) -> str:
    return " ".join(secret[i : i + 4] for i in range(0, len(secret), 4))


@router.get("/enrol")
async def enrol_form(request: Request, db: DbSession) -> HTMLResponse:
    admin_id = _read_pending(request.cookies.get(PENDING_COOKIE))
    # Also allow an already-signed-in-but-unenrolled admin (edge case).
    if admin_id is None:
        admin = await security.session_admin(
            db, request.cookies.get(config.COOKIE_NAME)
        )
        admin_id = str(admin.id) if admin else None
    if admin_id is None:
        return RedirectResponse("/sign-in", status_code=303)
    admin = await db.get(AdminUser, admin_id)
    if admin is None:
        return RedirectResponse("/sign-in", status_code=303)
    if admin.totp_enrolled_at is not None:
        return RedirectResponse("/sign-in/2fa", status_code=303)

    # Fresh secret + recovery codes each visit until confirmed, so an abandoned
    # enrolment never leaves a half-known secret usable.
    secret = security.new_totp_secret()
    codes = security.generate_recovery_codes()
    admin.totp_secret = secret
    await db.commit()
    await security.store_recovery_codes(db, admin.id, codes)

    qr = segno.make(security.totp_uri(secret, admin.email), error="m")
    qr_svg = qr.svg_inline(scale=4, dark="#2B2118", light="#ffffff")
    return _render(
        request,
        "enrol.html",
        qr_svg=qr_svg,
        secret_grouped=_grouped(secret),
        recovery_codes=codes,
    )


@router.post("/enrol")
async def enrol(request: Request, db: DbSession, code: str = Form(...)) -> HTMLResponse:
    admin_id = _read_pending(request.cookies.get(PENDING_COOKIE))
    if admin_id is None:
        admin = await security.session_admin(
            db, request.cookies.get(config.COOKIE_NAME)
        )
        admin_id = str(admin.id) if admin else None
    if admin_id is None:
        return RedirectResponse("/sign-in", status_code=303)
    admin = await db.get(AdminUser, admin_id)
    if admin is None or admin.totp_secret is None:
        return RedirectResponse("/sign-in", status_code=303)
    if not security.verify_totp(admin.totp_secret, code):
        # Re-render with a fresh QR so the codes on screen still match the secret.
        qr = segno.make(security.totp_uri(admin.totp_secret, admin.email), error="m")
        return _render(
            request,
            "enrol.html",
            qr_svg=qr.svg_inline(scale=4, dark="#2B2118", light="#ffffff"),
            secret_grouped=_grouped(admin.totp_secret),
            recovery_codes=[],
            flash={
                "kind": "err",
                "text": "That code didn't match — scan again and use the current one.",
            },
        )
    from datetime import UTC, datetime

    admin.totp_enrolled_at = datetime.now(UTC)
    await db.commit()
    await security.audit(db, "admin.enrol", admin_id=admin.id, ip=client_ip(request))
    return await _complete_sign_in(request, db, admin)


# ---- sign out ------------------------------------------------------------
@router.get("/sign-out")
async def sign_out(request: Request, db: DbSession) -> RedirectResponse:
    await security.revoke_session(db, request.cookies.get(config.COOKIE_NAME))
    resp = RedirectResponse("/sign-in", status_code=303)
    resp.delete_cookie(config.COOKIE_NAME, path="/")
    resp.delete_cookie(PENDING_COOKIE, path="/")
    return resp
