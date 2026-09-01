"""The handbook's two pages: the contents, and a topic.

Content lives in `console/handbook.py`; this only decides what a given admin may
read and renders it. Role filtering is real, not cosmetic — a moderator reading
about the campaign composer would be reading about a menu item they will never
see.
"""

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from .. import handbook, queries
from ..deps import CurrentAdmin, DbSession
from ..templating import templates

router = APIRouter(prefix="/handbook")


@router.get("")
async def contents(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "handbook.html",
        {
            "admin": admin,
            "active": "handbook",
            "badges": await queries.nav_badges(db),
            "topics": handbook.visible(admin.role),
        },
    )


@router.get("/{slug}")
async def topic(request: Request, admin: CurrentAdmin, db: DbSession, slug: str) -> Response:
    found = handbook.BY_SLUG.get(slug)
    # A topic above this admin's role is answered the same way as one that
    # doesn't exist — the contents page, with no explanation of what they are
    # missing.
    if found is None or handbook.RANK[found.role] > handbook.RANK.get(admin.role, 0):
        return RedirectResponse("/handbook", status_code=303)
    return templates.TemplateResponse(
        request,
        "handbook_topic.html",
        {
            "admin": admin,
            "active": "handbook",
            "badges": await queries.nav_badges(db),
            "topic": found,
            "topics": handbook.visible(admin.role),
            "fmt": handbook.fmt,
        },
    )
