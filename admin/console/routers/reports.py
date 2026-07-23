"""Reported content — reader reports of public reviews (the only reader-written
text other readers see). Upholding a report *hides* the review: its `visible`
flag flips off (soft, reversible) and its server_seq bumps so the change syncs
to devices. The row is never destroyed. [WIRED]: quiet until the in-app report
button ships, but fully functional against the content_reports table now.
"""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import select, text, update

from .. import queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import (
    REPORT_DISMISSED,
    REPORT_OPEN,
    REPORT_UPHELD,
    ContentReport,
    Profile,
    Review,
)
from ..templating import templates

router = APIRouter(prefix="/moderation")


async def _open_reports(db: DbSession) -> list[dict]:
    """Open reports grouped to their review — with how many readers flagged it,
    the review body/author, and whether it's already hidden."""
    rows = (
        await db.execute(
            select(ContentReport, Review, Profile.full_name, Profile.username)
            .join(Review, Review.id == ContentReport.target_id)
            .outerjoin(Profile, Profile.id == Review.user_id)
            .where(ContentReport.status == REPORT_OPEN, ContentReport.target_type == "review")
            .order_by(ContentReport.created_at.desc())
        )
    ).all()
    by_review: dict = {}
    for report, review, full_name, username in rows:
        entry = by_review.setdefault(
            review.id,
            {
                "review": review,
                "author": full_name or (f"@{username}" if username else "a reader"),
                "count": 0,
                "report_ids": [],
                "reasons": set(),
            },
        )
        entry["count"] += 1
        entry["report_ids"].append(str(report.id))
        if report.reason:
            entry["reasons"].add(report.reason)
    return list(by_review.values())


@router.get("/reports")
async def reports(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    items = await _open_reports(db)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "reports.html",
        {"admin": admin, "active": "reports", "badges": badges, "items": items, "flash": flash},
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


async def _close_reports_for(
    db: DbSession, review_id: uuid.UUID, status_value: str, admin_id
) -> None:
    await db.execute(
        update(ContentReport)
        .where(ContentReport.target_id == review_id, ContentReport.status == REPORT_OPEN)
        .values(status=status_value, decided_by_admin_id=admin_id, decided_at=datetime.now(UTC))
    )


@router.post("/reports/{review_id}/uphold")
async def uphold(
    request: Request, admin: CurrentAdmin, db: DbSession, review_id: uuid.UUID
) -> RedirectResponse:
    resp = RedirectResponse("/moderation/reports", status_code=303)
    review = await db.get(Review, review_id)
    if review is None:
        set_flash(resp, "err", "That review no longer exists.")
        return resp
    # Hide it: flip visibility, bump server_seq so the reader's device pulls it.
    review.visible = False
    review.server_seq = text("nextval('sync_seq')")
    review.updated_at = datetime.now(UTC)
    await _close_reports_for(db, review_id, REPORT_UPHELD, admin.id)
    await db.commit()
    await security.audit(
        db,
        "review.hide",
        admin_id=admin.id,
        target_type="review",
        target_id=str(review_id),
        summary="report upheld",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Review hidden. It's kept, not deleted — reversible later.")
    return resp


@router.post("/reports/{review_id}/dismiss")
async def dismiss(
    request: Request, admin: CurrentAdmin, db: DbSession, review_id: uuid.UUID
) -> RedirectResponse:
    resp = RedirectResponse("/moderation/reports", status_code=303)
    await _close_reports_for(db, review_id, REPORT_DISMISSED, admin.id)
    await db.commit()
    await security.audit(
        db,
        "report.dismiss",
        admin_id=admin.id,
        target_type="review",
        target_id=str(review_id),
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Report dismissed — no violation.")
    return resp
