"""Time-series and "right now" queries — the numbers behind the dashboard's
live view.

Kept apart from `queries.py` because those are *state* questions ("how many are
waiting on me") answered by a COUNT, while these are *movement* questions ("how
many arrived today, and is that more than last week") answered by grouping rows
into days. The two have different shapes, different cache lifetimes and
different failure modes, so they get different modules.

Everything here is read-only and global — no per-reader private data passes
through. Days are **UTC** days (CLAUDE.md rule 5): `date(timezone('UTC', col))`,
so a bucket means the same thing whatever region the container runs in.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import cache
from .models_ref import (
    ActiveReadingSession,
    Author,
    Edition,
    LibraryEntry,
    Profile,
    Publisher,
    ReadingSession,
    Review,
    SyncOp,
    Work,
)

# The windows the dashboard offers. Value is the number of days shown.
RANGES = {"7": 7, "28": 28, "90": 90}
DEFAULT_RANGE = "28"

# The series drawn on the growth chart, in the order the legend lists them.
SERIES = (
    ("readers", "New readers", "var(--oxblood)"),
    ("shelved", "Books shelved", "var(--gold)"),
    ("works", "Works added", "var(--moss)"),
    ("reviews", "Reviews", "var(--slate)"),
)


def _utc_day(col):  # noqa: ANN001, ANN202 — SQLAlchemy column expression
    """The UTC calendar day a timestamptz falls in, as a `date`."""
    return func.date(func.timezone("UTC", col))


async def _daily(db: AsyncSession, column, since: date, *conds) -> dict[date, int]:  # noqa: ANN001
    """`{day: count}` for rows whose `column` falls on or after `since`."""
    day = _utc_day(column)
    rows = (
        await db.execute(
            select(day.label("d"), func.count())
            .where(column >= since, *conds)
            .group_by(day)
            .order_by(day)
        )
    ).all()
    return {r[0]: int(r[1]) for r in rows}


def _fill(buckets: dict[date, int], days: list[date]) -> list[int]:
    """A dense list aligned to `days` — a day with no rows is a real zero, not a
    gap. A chart that skips empty days lies about the shape of the curve."""
    return [int(buckets.get(d, 0)) for d in days]


def day_axis(days: int, today: date | None = None) -> list[date]:
    """The `days` calendar days ending today (inclusive), oldest first."""
    today = today or datetime.now(UTC).date()
    return [today - timedelta(days=n) for n in range(days - 1, -1, -1)]


def delta(current: int, previous: int) -> dict:
    """The change between two equal-length windows, as the dashboard shows it.

    `pct` is None when the previous window was empty — "up 100%" from zero is
    arithmetic, not information, and a percentage nobody can act on is worse
    than an honest blank.
    """
    diff = current - previous
    pct = round(100 * diff / previous) if previous else None
    return {"diff": diff, "pct": pct, "up": diff > 0, "down": diff < 0, "flat": diff == 0}


def spark(
    values: list[int], width: float = 100.0, height: float = 34.0, peak: int | None = None
) -> dict:
    """Turn a series into SVG geometry: a line path, a filled area path and the
    point coordinates (for hover targets).

    Pure and unit-tested — the chart is drawn with no JavaScript and no chart
    library (the console has no build step), so this is where the whole drawing
    is decided. The viewBox is a fixed 100×`height` grid the SVG scales to any
    width, which is why the caller never passes real pixels.

    `peak` overrides the value the top of the grid represents. It exists for the
    one case where it matters: **several series drawn on one chart must share a
    scale.** Left to itself each series is normalised to its own maximum, so a
    day with 59 shelvings and a day with 16 reviews both touch the ceiling and
    the picture says they are equal. Sparklines beside their own number keep the
    default, because there the shape is the point and the number is right there.
    """
    n = len(values)
    if n == 0:
        return {"line": "", "area": "", "points": [], "max": 0}
    ceiling = max(values) if peak is None else peak
    # A flat-zero series draws along the floor rather than dividing by zero.
    span = ceiling or 1
    step = width / (n - 1) if n > 1 else 0.0
    pts = []
    for i, v in enumerate(values):
        x = round(i * step, 2) if n > 1 else round(width / 2, 2)
        # 1px of headroom top and bottom so the peak isn't clipped by the edge.
        y = round(height - 1 - (v / span) * (height - 2), 2)
        pts.append({"x": x, "y": y, "v": v})
    line = "M" + " L".join(f"{p['x']},{p['y']}" for p in pts)
    area = f"{line} L{pts[-1]['x']},{height} L{pts[0]['x']},{height} Z"
    return {"line": line, "area": area, "points": pts, "max": ceiling}


async def growth(db: AsyncSession, days: int) -> dict:
    """Per-day arrivals over the last `days` days, plus the same figure for the
    window before it so every KPI can carry a direction.

    Cached for 3 minutes: it is ~8 grouped counts, and a growth curve that is
    three minutes stale is still the same curve.
    """
    return await cache.get_or_compute(f"growth:{days}", 180, lambda: _growth(db, days))


async def _growth(db: AsyncSession, days: int) -> dict:
    axis = day_axis(days)
    # Two windows: the one shown, and the one immediately before it (same
    # length) which the deltas compare against.
    since = axis[0] - timedelta(days=days)
    prev_start, prev_end = since, axis[0]

    live = LibraryEntry.deleted_at.is_(None)
    sources = {
        "readers": (Profile.created_at, (Profile.deleted_at.is_(None),)),
        "shelved": (LibraryEntry.created_at, (live,)),
        "works": (Work.created_at, (Work.deleted_at.is_(None),)),
        "reviews": (Review.created_at, (Review.deleted_at.is_(None),)),
        "editions": (Edition.created_at, (Edition.deleted_at.is_(None),)),
        "authors": (Author.created_at, (Author.deleted_at.is_(None),)),
        "sessions": (ReadingSession.started_at, (ReadingSession.deleted_at.is_(None),)),
    }

    series: dict[str, list[int]] = {}
    totals: dict[str, int] = {}
    prev: dict[str, int] = {}
    for key, (column, conds) in sources.items():
        buckets = await _daily(db, column, since, *conds)
        series[key] = _fill(buckets, axis)
        totals[key] = sum(series[key])
        prev[key] = sum(v for d, v in buckets.items() if prev_start <= d < prev_end)

    return {
        "days": days,
        "axis": [d.isoformat() for d in axis],
        "labels": [d.strftime("%-d %b") for d in axis],
        "series": series,
        "totals": totals,
        "deltas": {k: delta(totals[k], prev[k]) for k in totals},
        # Two sets of geometry from one set of numbers: per-card sparklines,
        # each normalised to itself, and the shared-scale paths the combined
        # growth chart draws (see `spark`'s `peak`).
        "charts": {k: spark(v) for k, v in series.items()},
        "shared": {
            k: spark(v, peak=max((max(series[s], default=0) for s, _, _ in SERIES), default=0))
            for k, v in series.items()
        },
    }


async def pulse(db: AsyncSession) -> dict:
    """The "right now" strip. 15-second TTL — short enough to feel live, long
    enough that a page left open on a wall screen isn't a load generator."""
    return await cache.get_or_compute(cache.PULSE, 15, lambda: _pulse(db))


async def _pulse(db: AsyncSession) -> dict:
    now = datetime.now(UTC)
    today = now.date()
    day_ago = now - timedelta(hours=24)

    async def count(model, *conds) -> int:  # noqa: ANN002
        return int(await db.scalar(select(func.count()).select_from(model).where(*conds)) or 0)

    # Sittings running this second. `active_reading_sessions` holds exactly one
    # row per reader while a timer runs and is deleted on stop, so this is a
    # live number rather than a derived one.
    reading_now = int(await db.scalar(select(func.count()).select_from(ActiveReadingSession)) or 0)
    # Distinct readers whose device pushed anything in the last 24h — the
    # closest thing we have to "used the app today" without storing a
    # last-seen column on the reader.
    active_24h = int(
        await db.scalar(
            select(func.count(func.distinct(SyncOp.user_id))).where(SyncOp.applied_at >= day_ago)
        )
        or 0
    )
    minutes = int(
        await db.scalar(
            select(func.coalesce(func.sum(ReadingSession.duration_seconds), 0)).where(
                ReadingSession.deleted_at.is_(None),
                _utc_day(ReadingSession.started_at) == today,
            )
        )
        or 0
    )
    return {
        "reading_now": reading_now,
        "active_24h": active_24h,
        "new_readers_today": await count(
            Profile, Profile.deleted_at.is_(None), _utc_day(Profile.created_at) == today
        ),
        "shelved_today": await count(
            LibraryEntry,
            LibraryEntry.deleted_at.is_(None),
            _utc_day(LibraryEntry.created_at) == today,
        ),
        "reviews_today": await count(
            Review, Review.deleted_at.is_(None), _utc_day(Review.created_at) == today
        ),
        "works_today": await count(
            Work, Work.deleted_at.is_(None), _utc_day(Work.created_at) == today
        ),
        "minutes_today": round(minutes / 60),
        "as_of": now,
    }


async def reading_now_shape(db: AsyncSession) -> dict:
    """Aggregate context for the live count — never *who*.

    This deliberately does not name the readers or the books. The console's
    standing promise (see `routers/readers.py`) is that it never opens a
    reader's private shelf, notes or reading progress, and "Anaya is 40 minutes
    into Chemmeen right now" is exactly that, dressed as a dashboard. The count
    is what makes the panel live; the names would only make it surveillance.

    So: how many sittings, across how many different books, and how long the
    longest has been going — all of which describe the service rather than a
    person.
    """
    rows = (
        await db.execute(
            select(ActiveReadingSession.started_at, LibraryEntry.edition_id).outerjoin(
                LibraryEntry, LibraryEntry.id == ActiveReadingSession.library_entry_id
            )
        )
    ).all()
    if not rows:
        return {"sittings": 0, "books": 0, "longest_minutes": 0}
    now = datetime.now(UTC)
    minutes = []
    for started, _ in rows:
        if started.tzinfo is None:
            started = started.replace(tzinfo=UTC)
        minutes.append(max(0, round((now - started).total_seconds() / 60)))
    return {
        "sittings": len(rows),
        "books": len({edition for _, edition in rows if edition}),
        "longest_minutes": max(minutes),
    }


async def recent_readers(db: AsyncSession, limit: int = 8) -> list[Profile]:
    """The newest accounts, newest first — the dashboard's signup feed."""
    return list(
        (
            await db.execute(
                select(Profile)
                .where(Profile.deleted_at.is_(None))
                .order_by(Profile.created_at.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )


async def recent_catalog(db: AsyncSession, limit: int = 8) -> list[dict]:
    """The newest reader-visible catalog rows across works, authors and
    publishers, merged into one feed. Three small queries and a merge rather
    than a UNION so each keeps its own indexed ORDER BY.

    Only works and authors record a contributor — `publishers` has no
    `created_by_user_id` column — so a publisher row shows "Imported" rather
    than a name it cannot know.
    """
    feed: list[dict] = []
    for model, kind, href, label in (
        (Work, "work", "/catalog/works/", "Work"),
        (Author, "author", "/catalog/authors/", "Author"),
        (Publisher, "publisher", "/catalog/publishers/", "Publisher"),
    ):
        name_col = Work.title if model is Work else model.name
        has_adder = hasattr(model, "created_by_user_id")
        cols = [model.id, name_col, model.created_at]
        if has_adder:
            cols.append(model.created_by_user_id)
        rows = (
            await db.execute(
                select(*cols)
                .where(model.deleted_at.is_(None))
                .order_by(model.created_at.desc())
                .limit(limit)
            )
        ).all()
        for row in rows:
            feed.append(
                {
                    "kind": kind,
                    "label": label,
                    "id": row[0],
                    "name": row[1],
                    "created_at": row[2],
                    "adder_id": row[3] if has_adder else None,
                    "href": f"{href}{row[0]}",
                }
            )
    feed.sort(key=lambda r: r["created_at"], reverse=True)
    feed = feed[:limit]
    await attach_adders(db, feed)
    return feed


async def attach_adders(db: AsyncSession, rows: list[dict]) -> None:
    """Resolve every `adder_id` in `rows` to a display name in one query, in
    place. A row whose adder is gone (or which came from the bulk seed) reads
    "Imported" rather than a bare UUID."""
    ids = {r["adder_id"] for r in rows if r.get("adder_id")}
    names: dict[uuid.UUID, str] = {}
    if ids:
        found = (
            await db.execute(
                select(Profile.id, Profile.full_name, Profile.email).where(Profile.id.in_(ids))
            )
        ).all()
        names = {pid: (full or email) for pid, full, email in found}
    for r in rows:
        r["adder"] = names.get(r.get("adder_id")) if r.get("adder_id") else None
        r["adder_label"] = r["adder"] or "Imported"
