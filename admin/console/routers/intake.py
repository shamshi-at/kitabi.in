"""What the nightly intake put into the catalogue — by day, then book by book.

The intake (`api/app/jobs/catalog_intake.py`) runs at 02:30 IST with nobody
watching and publishes up to 150 books as public pages. Its first night
(4 Oct 2026) had to be read back out of the database with ad-hoc queries, and
eight of the books it published turned out to be ones it should not have. A
job that publishes unattended needs a screen where a person can see, every
morning, what it did.

Two views:

- **the days** — how many books each night published, and from which
  publisher's shop; beside it, what is still waiting and why.
- **one day** — every book published that night, with its cover, so a wrong
  one is seen rather than discovered later by a reader.

Read-only. Undoing a book is still a deliberate act with its own tool
(`api/scripts/revert_intake.py`), and editing one is the catalogue screens'
job; each row links to both places a person would go next.

**Columns, not rows.** `catalog_intake.payload` carries every book's whole
blurb, so `select(CatalogIntake)` for a day is megabytes out of a database
whose egress is metered (CLAUDE.md, 7 Sep 2026). The day view reads what was
*published* — the Work and Edition rows — and from the staging table takes
only the receipt.
"""

from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from sqlalchemy import func, select

from .. import queries
from ..deps import DbSession, RequireEditor
from ..flash import pop_flash
from ..models_ref import Author, CatalogIntake, Edition, Publisher, Work, work_authors
from ..templating import IST, templates, to_ist

router = APIRouter(prefix="/intake")

PROMOTED = "promoted"

#: Adapter name → what to call it on screen. An adapter not listed here shows
#: under its own name rather than disappearing.
SOURCES = {
    "harpercollins_in": "HarperCollins India",
    "mathrubhumi": "Mathrubhumi",
    "speakingtiger": "Speaking Tiger",
    "openlibrary_en": "OpenLibrary",
}

#: The gate's reasons, in the words of someone reading the queue.
WAITING = {
    "authors": "No author found yet",
    "language": "Language not known yet",
    "author_roles": "Several people credited — who wrote it is not clear",
    "title_script": "Title is not in the book's own script",
    "cover_url": "No usable cover",
    "isbn": "No ISBN",
    "isbn_invalid": "The ISBN is not a valid one",
    "publisher": "No publisher",
    "title": "No title",
    "possible_duplicate": "Same title as a book already here, different author",
}

#: How many nights the first view lists.
DAYS_SHOWN = 60


def source_label(source: str) -> str:
    return SOURCES.get(source, source)


def waiting_label(reason: str) -> str:
    return WAITING.get(reason, reason.replace("_", " "))


def _ist_day(column):
    """The IST calendar day of a timestamp column. The job runs at 02:30 IST, so
    a night's books all fall on one IST date whatever the server's zone — and it
    is the date the owner reads the night under. (Until 6 Oct 2026 the run was
    02:30 UTC, 08:00 IST: every night before that lands on the same date either
    way, so no earlier row moved.) The zone is Postgres's own, not ours."""
    return func.date(func.timezone("Asia/Kolkata", column))


def fold_days(published: list[tuple], found: list[tuple], limit: int = DAYS_SHOWN) -> list[dict]:
    """Per-day rows for the table, newest first.

    `published` is `(day, source, count)`; `found` is `(day, count)` — rows the
    crawl first saw that day, published or not. Pure, so the shape the template
    relies on is tested without a database.
    """
    days: dict[date, dict] = {}
    for day, source, count in published:
        row = days.setdefault(day, {"day": day, "published": 0, "by_source": {}, "found": 0})
        row["published"] += count
        row["by_source"][source] = row["by_source"].get(source, 0) + count
    for day, count in found:
        row = days.setdefault(day, {"day": day, "published": 0, "by_source": {}, "found": 0})
        row["found"] = count
    ordered = sorted(days.values(), key=lambda r: r["day"], reverse=True)[:limit]
    peak = max((r["published"] for r in ordered), default=0)
    for row in ordered:
        row["share"] = round(100 * row["published"] / peak) if peak else 0
    return ordered


#: A night is not judged until it has had this long to finish (the first two
#: took ~20 min; the Kerala Book Store step can add 25 more).
RUN_SETTLES_AFTER = timedelta(hours=1)


def run_at() -> tuple[int, int]:
    """When the job runs, as an IST clock time — `(2, 30)`.

    Read from the same two settings the scheduler registers its cron from
    (`catalog_intake_run_hour_utc` / `_minute_utc`), so the screen and the
    schedule are one decision and cannot be moved apart by editing one of them.
    """
    from app.core.config import (
        get_settings,
    )  # noqa: PLC0415 — lazy, keeps the import cheap

    settings = get_settings()
    at = datetime(
        2000,
        1,
        1,
        settings.catalog_intake_run_hour_utc,
        settings.catalog_intake_run_minute_utc,
        tzinfo=UTC,
    )
    local = to_ist(at)
    return local.hour, local.minute


def short_night(days: list[dict], ready: int, limit: int, now: datetime) -> dict | None:
    """Say so when the last run fell far short — or left no trace at all.

    On 5 Oct 2026 the job crashed two seconds into publishing: one book out,
    1,070 ready, and the only record was a traceback in a server log nobody
    reads. The owner found it by noticing the number on this screen. A job
    that publishes unattended has to report its own bad nights, here, in words.

    "Far short" is under half the nightly limit while a full night's worth was
    ready. A little short is ordinary — a cover that would not load, a book
    that turned out to be here already — and is not worth a warning.

    Pure: `days` is `fold_days`' output, `now` is passed in.
    """
    hour, minute = run_at()
    now = to_ist(now)
    last_run = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if now < last_run + RUN_SETTLES_AFTER:
        last_run -= timedelta(days=1)
    night = last_run.date()
    row = next((d for d in days if d["day"] == night), None)
    if not days:
        return None  # the intake has never run; nothing is late
    if row is None:
        return {
            "day": night,
            "kind": "missing",
            "published": 0,
            "ready": ready,
            "limit": limit,
        }
    if row["published"] < limit / 2 and ready >= limit:
        return {
            "day": night,
            "kind": "short",
            "published": row["published"],
            "ready": ready,
            "limit": limit,
        }
    return None


def daily_limit() -> int:
    from app.core.config import (
        get_settings,
    )  # noqa: PLC0415 — lazy, keeps the import cheap

    return get_settings().catalog_intake_daily_limit


async def _days(db: DbSession) -> list[dict]:
    published_day = _ist_day(CatalogIntake.promoted_at)
    published = (
        await db.execute(
            select(published_day, CatalogIntake.source, func.count())
            .where(CatalogIntake.state == PROMOTED, CatalogIntake.promoted_at.is_not(None))
            .group_by(published_day, CatalogIntake.source)
        )
    ).all()
    found_day = _ist_day(CatalogIntake.first_seen_at)
    found = (await db.execute(select(found_day, func.count()).group_by(found_day))).all()
    return fold_days([tuple(r) for r in published], [tuple(r) for r in found])


async def _queue(db: DbSession) -> dict:
    """How many rows are in each state, and what the held ones wait for."""
    # An undone book goes back to the queue with `promoted_at` cleared, so it
    # leaves its night's count — a night that published 150 reads 142 after
    # eight are undone. Nothing durable records that it was ever out (the
    # "reverted" note is overwritten by the next re-screen), so no "undone"
    # figure is shown: one that decays overnight is worse than none.
    states = dict(
        (await db.execute(select(CatalogIntake.state, func.count()).group_by(CatalogIntake.state)))
        .tuples()
        .all()
    )
    # One row per reason: a book waiting on two things is counted under both,
    # which is what the caption on the screen says.
    reason = func.jsonb_array_elements_text(CatalogIntake.missing).label("reason")
    per_reason = (
        select(reason).where(
            CatalogIntake.state == "incomplete", CatalogIntake.missing.is_not(None)
        )
    ).subquery()
    waiting = (
        await db.execute(
            select(per_reason.c.reason, func.count())
            .group_by(per_reason.c.reason)
            .order_by(func.count().desc())
        )
    ).all()
    return {
        "published": states.get(PROMOTED, 0),
        "ready": states.get("complete", 0),
        "held": states.get("incomplete", 0),
        "refused": states.get("rejected", 0),
        "duplicate": states.get("duplicate", 0),
        "waiting": [{"label": waiting_label(r), "count": n} for r, n in waiting],
    }


async def _books(db: DbSession, day: date, source: str | None) -> list[dict]:
    """Every book published on `day`, as it stands in the catalogue now."""
    start = datetime(day.year, day.month, day.day, tzinfo=IST)
    stmt = (
        select(
            CatalogIntake.source,
            CatalogIntake.promoted_at,
            CatalogIntake.payload.has_key("_printing"),  # noqa: W601 — JSONB `?`
            Work.id,
            Work.title,
            Work.subtitle,
            Work.slug,
            Work.language,
            Work.deleted_at,
            Edition.isbn,
            Edition.cover_url,
            Edition.page_count,
            Edition.format,
            Publisher.name,
        )
        .join(Work, Work.id == CatalogIntake.work_id)
        .outerjoin(Edition, Edition.id == CatalogIntake.edition_id)
        .outerjoin(Publisher, Publisher.id == Edition.publisher_id)
        .where(
            CatalogIntake.state == PROMOTED,
            CatalogIntake.promoted_at >= start,
            CatalogIntake.promoted_at < start + timedelta(days=1),
        )
        .order_by(CatalogIntake.promoted_at, CatalogIntake.id)
    )
    if source:
        stmt = stmt.where(CatalogIntake.source == source)
    rows = (await db.execute(stmt)).all()

    names: dict = {}
    work_ids = list({r[3] for r in rows})
    if work_ids:
        credited = await db.execute(
            select(work_authors.c.work_id, Author.name)
            .join(Author, Author.id == work_authors.c.author_id)
            .where(work_authors.c.work_id.in_(work_ids))
        )
        for work_id, name in credited.all():
            names.setdefault(work_id, []).append(name)

    return [
        {
            "source": source_label(src),
            "at": at,
            "printing": bool(printing),
            "work_id": work_id,
            "title": title,
            "subtitle": subtitle,
            "slug": slug,
            "language": language,
            "removed": removed is not None,
            "isbn": isbn,
            "cover_url": cover,
            "pages": pages,
            "format": fmt,
            "publisher": publisher,
            "authors": ", ".join(names.get(work_id, [])),
        }
        for (
            src,
            at,
            printing,
            work_id,
            title,
            subtitle,
            slug,
            language,
            removed,
            isbn,
            cover,
            pages,
            fmt,
            publisher,
        ) in rows
    ]


def parse_day(value: str) -> date | None:
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


@router.get("")
async def index(request: Request, admin: RequireEditor, db: DbSession) -> HTMLResponse:
    days = await _days(db)
    queue = await _queue(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "intake.html",
        {
            "admin": admin,
            "active": "intake",
            "badges": await queries.nav_badges(db),
            "days": days,
            "sources": [s for s in SOURCES if any(s in d["by_source"] for d in days)],
            "source_label": source_label,
            "queue": queue,
            "short": short_night(days, queue["ready"], daily_limit(), datetime.now(UTC)),
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.get("/{day}")
async def one_day(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    day: str,
    source: str = Query(default=""),
) -> Response:
    when = parse_day(day)
    if when is None:
        return RedirectResponse("/intake", status_code=303)
    source = source if source in SOURCES else ""
    books = await _books(db, when, source or None)
    return templates.TemplateResponse(
        request,
        "intake_day.html",
        {
            "admin": admin,
            "active": "intake",
            "badges": await queries.nav_badges(db),
            "day": when,
            "books": books,
            "sources": SOURCES,
            "source": source,
            "previous": when - timedelta(days=1),
            "next": (when + timedelta(days=1) if when < to_ist(datetime.now(UTC)).date() else None),
            "flash": None,
        },
    )
