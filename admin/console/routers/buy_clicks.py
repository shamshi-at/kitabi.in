"""Buy-link clicks — which books readers go on to look at buying.

The affiliate button has been on every book page since August with nothing
counting what it does. Amazon's own report says how many orders a tag earned;
it never says which of *our* pages sent them, or that a book is opened in the
shop fifty times a week and never bought. `buy_clicks` (api/app/models) is the
missing half, and this is where it is read (owner request, 5 Oct 2026).

One screen, one window: the totals, the days, the shops, the books, and the
most recent clicks themselves — who, which book, which shop, from the app or
the website.

**It names readers, so opening it is audited.** A reader's taps on a buy link
are their own behaviour, and the rule for the console since 4 Oct 2026 is that
an operator may see a reader's private data *because* every look is recorded:
a `privacy.view` line, written here on the page load, as `routers/activity.py`
does. Website clicks have nobody to name — the table stores nothing about a
visitor — and show as such.

**Nothing here says Amazon.** There is one shop today and the owner expects
more; the shop column is whatever keys the rows carry, so a second shop shows
up in this report the day its first click arrives.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import func, select

from .. import queries, security
from ..deps import DbSession, RequireEditor, client_ip
from ..models_ref import BuyClick, Profile, Work
from ..templating import templates

router = APIRouter(prefix="/buy-clicks")

#: The windows the screen offers: key → (label, days back, or None for all).
WINDOWS: dict[str, tuple[str, int | None]] = {
    "7": ("Last 7 days", 7),
    "28": ("Last 28 days", 28),
    "90": ("Last 90 days", 90),
    "all": ("All time", None),
}
DEFAULT_WINDOW = "28"

#: What a click's `surface` is called on screen.
SURFACES = {"app": "App", "web": "Website"}

TOP_BOOKS = 25
RECENT = 100


def shop_label(key: str) -> str:
    """`amazon` → `Amazon`. A key nobody has heard of still reads as a name."""
    return key.replace("_", " ").replace("-", " ").title() if key else "—"


def surface_label(key: str) -> str:
    return SURFACES.get(key, key or "—")


def window_start(key: str, now: datetime) -> datetime | None:
    """The instant a window opens, or None for "all time". Whole UTC days, so
    "last 7 days" is today and the six before it — the same seven the day
    table shows."""
    days = WINDOWS.get(key, WINDOWS[DEFAULT_WINDOW])[1]
    if days is None:
        return None
    today = now.astimezone(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
    return today - timedelta(days=days - 1)


def fold_days(rows: list[tuple], start: date | None, today: date) -> list[dict]:
    """Per-day rows for the table, newest first, with the quiet days kept.

    `rows` is `(day, surface, count)`. A day with no clicks is a real zero and
    is shown as one: a table that skips it makes a dead week look like a
    shorter list. With no `start` ("all time") the span begins at the first
    click. Pure, so the shape the template relies on is tested without a
    database.
    """
    per: dict[date, dict[str, int]] = {}
    for day, surface, count in rows:
        per.setdefault(day, {})[surface] = per.setdefault(day, {}).get(surface, 0) + count
    first = start or (min(per) if per else today)
    days = []
    day = today
    while day >= first:
        by = per.get(day, {})
        days.append(
            {
                "day": day,
                "app": by.get("app", 0),
                "web": by.get("web", 0),
                "total": sum(by.values()),
            }
        )
        day -= timedelta(days=1)
    peak = max((d["total"] for d in days), default=0)
    for d in days:
        d["share"] = round(100 * d["total"] / peak) if peak else 0
    return days


def with_shares(rows: list[dict], total: int) -> list[dict]:
    """Add each row's percentage of `total`, for the shop and book tables."""
    return [{**r, "share": round(100 * r["clicks"] / total) if total else 0} for r in rows]


def display_name(profile) -> str:  # noqa: ANN001 — a Profile row or None
    if profile is None:
        return "a deleted account"
    return profile.full_name or (f"@{profile.username}" if profile.username else profile.email)


def _in_window(start: datetime | None) -> list:
    return [BuyClick.occurred_at >= start] if start is not None else []


async def _totals(db: DbSession, start: datetime | None) -> dict:
    row = (
        await db.execute(
            select(
                func.count(),
                func.count(func.distinct(BuyClick.user_id)),
                func.count(func.distinct(BuyClick.work_id)),
                func.count().filter(BuyClick.surface == "app"),
                func.count().filter(BuyClick.surface == "web"),
                func.count().filter(BuyClick.affiliate.is_(True)),
            ).where(*_in_window(start))
        )
    ).one()
    return {
        "clicks": row[0],
        "readers": row[1],
        "books": row[2],
        "app": row[3],
        "web": row[4],
        "tagged": row[5],
    }


async def _days(db: DbSession, start: datetime | None, now: datetime) -> list[dict]:
    day = func.date(func.timezone("UTC", BuyClick.occurred_at))
    rows = (
        await db.execute(
            select(day, BuyClick.surface, func.count())
            .where(*_in_window(start))
            .group_by(day, BuyClick.surface)
        )
    ).all()
    return fold_days(
        [tuple(r) for r in rows],
        start.date() if start is not None else None,
        now.astimezone(UTC).date(),
    )


async def _shops(db: DbSession, start: datetime | None, total: int) -> list[dict]:
    rows = (
        await db.execute(
            select(
                BuyClick.retailer,
                func.count(),
                func.count(func.distinct(BuyClick.work_id)),
                func.count().filter(BuyClick.surface == "app"),
                func.count().filter(BuyClick.surface == "web"),
            )
            .where(*_in_window(start))
            .group_by(BuyClick.retailer)
            .order_by(func.count().desc())
        )
    ).all()
    return with_shares(
        [
            {
                "key": key,
                "label": shop_label(key),
                "clicks": n,
                "books": books,
                "app": app,
                "web": web,
            }
            for key, n, books, app, web in rows
        ],
        total,
    )


async def _books(db: DbSession, start: datetime | None, total: int) -> list[dict]:
    rows = (
        await db.execute(
            select(
                BuyClick.work_id,
                Work.title,
                func.count(),
                func.count().filter(BuyClick.surface == "app"),
                func.count().filter(BuyClick.surface == "web"),
                func.count(func.distinct(BuyClick.user_id)),
                func.max(BuyClick.occurred_at),
            )
            .join(Work, Work.id == BuyClick.work_id)
            .where(*_in_window(start))
            .group_by(BuyClick.work_id, Work.title)
            .order_by(func.count().desc(), func.max(BuyClick.occurred_at).desc())
            .limit(TOP_BOOKS)
        )
    ).all()
    return with_shares(
        [
            {
                "work_id": work_id,
                "title": title,
                "clicks": n,
                "app": app,
                "web": web,
                "readers": readers,
                "last": last,
            }
            for work_id, title, n, app, web, readers, last in rows
        ],
        total,
    )


async def _recent(db: DbSession, start: datetime | None) -> list[dict]:
    rows = (
        await db.execute(
            select(
                BuyClick.occurred_at,
                BuyClick.user_id,
                BuyClick.work_id,
                Work.title,
                BuyClick.retailer,
                BuyClick.surface,
                BuyClick.affiliate,
            )
            .join(Work, Work.id == BuyClick.work_id)
            .where(*_in_window(start))
            .order_by(BuyClick.occurred_at.desc())
            .limit(RECENT)
        )
    ).all()
    reader_ids = {user_id for _, user_id, *_ in rows if user_id is not None}
    readers = {}
    if reader_ids:
        found = await db.execute(select(Profile).where(Profile.id.in_(reader_ids)))
        readers = {p.id: p for p in found.scalars()}
    return [
        {
            "at": at,
            "reader_id": user_id,
            # A website click has nobody behind it to name — not "unknown".
            "reader": display_name(readers.get(user_id)) if user_id is not None else None,
            "work_id": work_id,
            "title": title,
            "shop": shop_label(retailer),
            "surface": surface_label(surface),
            "tagged": bool(affiliate),
        }
        for at, user_id, work_id, title, retailer, surface, affiliate in rows
    ]


@router.get("")
async def report(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    range_: str = Query(default=DEFAULT_WINDOW, alias="range"),
) -> HTMLResponse:
    range_ = range_ if range_ in WINDOWS else DEFAULT_WINDOW
    now = datetime.now(UTC)
    start = window_start(range_, now)
    totals = await _totals(db, start)
    recent = await _recent(db, start)

    # The list below names readers. Recorded on the page load, once — the
    # condition the owner attached to seeing a reader's own behaviour at all.
    await security.audit(
        db,
        "privacy.view",
        admin_id=admin.id,
        summary=f"Buy clicks · everyone · {WINDOWS[range_][0].lower()}",
        ip=client_ip(request),
    )

    return templates.TemplateResponse(
        request,
        "buy_clicks.html",
        {
            "admin": admin,
            "active": "buyclicks",
            "badges": await queries.nav_badges(db),
            "windows": {key: label for key, (label, _) in WINDOWS.items()},
            "range_key": range_,
            "window_label": WINDOWS[range_][0],
            "totals": totals,
            "days": await _days(db, start, now),
            "shops": await _shops(db, start, totals["clicks"]),
            "books": await _books(db, start, totals["clicks"]),
            "recent": recent,
            "recent_limit": RECENT,
            "flash": None,
        },
    )
