"""Global search — one box, reachable from every page, that recommends actions,
books, authors, publishers and readers. Returns an HTML fragment the top-bar
search dropdown injects (no client framework; a little vanilla JS in admin.js).

Results are role-aware: an action or a result group is only offered when the
admin can actually reach the page it links to, so nothing in the dropdown 404s
or bounces to a denied redirect.
"""

from app.services import catalog_service  # noqa: E402
from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import or_, select

from ..deps import CurrentAdmin, DbSession
from ..models_ref import Profile
from ..templating import templates

router = APIRouter()

_RANK = {"moderator": 0, "editor": 1, "super_admin": 2}

# The command palette. `role` is the minimum role; `keys` are extra match terms
# so "logout", "suspend", "duplicate" find the right action without being the
# visible label.
_ACTIONS = [
    {"label": "Dashboard", "href": "/", "keys": "home overview stats", "role": "moderator"},
    {
        "label": "Author claims",
        "href": "/moderation/claims",
        "keys": "claims this is me moderation",
        "role": "moderator",
    },
    {
        "label": "Suggested edits",
        "href": "/moderation/edits",
        "keys": "edits revisions moderation",
        "role": "editor",
    },
    {
        "label": "Reported content",
        "href": "/moderation/reports",
        "keys": "reports abuse flag reviews",
        "role": "moderator",
    },
    {
        "label": "Works & editions",
        "href": "/catalog",
        "keys": "books works catalog merge duplicate",
        "role": "editor",
    },
    {"label": "Authors", "href": "/catalog/authors", "keys": "authors writers", "role": "editor"},
    {
        "label": "Publishers",
        "href": "/catalog/publishers",
        "keys": "publishers houses imprint",
        "role": "editor",
    },
    {
        "label": "Readers",
        "href": "/readers",
        "keys": "readers users accounts suspend support",
        "role": "moderator",
    },
    {
        "label": "Admin users",
        "href": "/admins",
        "keys": "admins invite roles staff team",
        "role": "super_admin",
    },
    {
        "label": "Audit log",
        "href": "/audit",
        "keys": "audit trail history log",
        "role": "moderator",
    },
    {
        "label": "Change my password",
        "href": "/account/password",
        "keys": "password change account security",
        "role": "moderator",
    },
    {"label": "Sign out", "href": "/sign-out", "keys": "logout signout exit", "role": "moderator"},
]


def _can(admin, role: str) -> bool:
    return _RANK.get(admin.role, -1) >= _RANK[role]


@router.get("/search")
async def search(
    request: Request, admin: CurrentAdmin, db: DbSession, q: str = Query(default="")
) -> HTMLResponse:
    q = q.strip()
    ql = q.lower()
    actions = []
    books = authors = publishers = readers = []

    if ql:
        actions = [
            a
            for a in _ACTIONS
            if _can(admin, a["role"]) and (ql in a["label"].lower() or ql in a["keys"])
        ][:6]

        if _can(admin, "editor"):
            books = (await catalog_service.search_local(db, q))[:5]
            authors = await catalog_service.search_authors(db, q, limit=5)
            publishers = await catalog_service.search_publishers(db, q, limit=5)

        # Readers — any admin. Name / handle / email.
        like = f"%{q}%"
        readers = (
            (
                await db.execute(
                    select(Profile)
                    .where(
                        Profile.deleted_at.is_(None),
                        or_(
                            Profile.full_name.ilike(like),
                            Profile.username.ilike(like),
                            Profile.email.ilike(like),
                        ),
                    )
                    .limit(5)
                )
            )
            .scalars()
            .all()
        )

    has_any = any([actions, books, authors, publishers, readers])
    return templates.TemplateResponse(
        request,
        "_search_results.html",
        {
            "q": q,
            "actions": actions,
            "books": books,
            "authors": authors,
            "publishers": publishers,
            "readers": readers,
            "has_any": has_any,
        },
    )
