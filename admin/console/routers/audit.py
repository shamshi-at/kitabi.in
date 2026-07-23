"""The append-only audit log, and the "planned" stubs for sections whose full
build is deferred (edits, reports, catalog, readers) — so the nav is honest
rather than 404-ing on a link. Each stub still shows its real pending count."""

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import select

from .. import queries
from ..deps import CurrentAdmin, DbSession
from ..models_ref import AdminAuditLog
from ..templating import templates

router = APIRouter()


@router.get("/audit")
async def audit_log(
    request: Request, admin: CurrentAdmin, db: DbSession
) -> HTMLResponse:
    rows = (
        (
            await db.execute(
                select(AdminAuditLog)
                .order_by(AdminAuditLog.created_at.desc())
                .limit(200)
            )
        )
        .scalars()
        .all()
    )
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "audit.html",
        {"admin": admin, "active": "audit", "badges": badges, "rows": rows},
    )


def _planned(key: str, title: str, blurb: str):
    async def _view(
        request: Request, admin: CurrentAdmin, db: DbSession
    ) -> HTMLResponse:
        badges = await queries.nav_badges(db)
        return templates.TemplateResponse(
            request,
            "planned.html",
            {
                "admin": admin,
                "active": key,
                "badges": badges,
                "title": title,
                "blurb": blurb,
            },
        )

    return _view


router.add_api_route(
    "/moderation/edits",
    _planned(
        "edits",
        "Suggested edits",
        "The escalation queue for catalog edits — seeded books with no contributor, and edits an admin wants "
        "to overrule. Readers already review edits to books they added; this screen extends that to everything "
        "else. Designed in the mockups (S6); wiring is the next slice.",
    ),
    methods=["GET"],
)

router.add_api_route(
    "/moderation/reports",
    _planned(
        "reports",
        "Reported content",
        "Reported public reviews. The content_reports table and the report action are already in the schema "
        "([WIRED]); this queue stays quiet until the in-app report button ships and there is traffic.",
    ),
    methods=["GET"],
)

router.add_api_route(
    "/catalog",
    _planned(
        "catalog",
        "Works & editions",
        "Catalog operations — search with the same spelling-fold the app uses, duplicate merge with a preview "
        "of what moves, and a quality-gap worklist. The highest-risk screen (merge moves other readers' library "
        "entries), so it is built last and most carefully.",
    ),
    methods=["GET"],
)

router.add_api_route(
    "/readers",
    _planned(
        "readers",
        "Readers",
        "Find an account, see its public identity and contribution counts, and act when it misbehaves — never "
        "its private shelf. Support, not surveillance. Next slice.",
    ),
    methods=["GET"],
)
