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
from typing import NamedTuple

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
from .templating import to_ist


class Range(NamedTuple):
    """One window the dashboard offers: how many buckets, of what size."""

    buckets: int
    unit: str  # "day" | "hour"
    label: str  # "7 days" — headings
    short: str  # "7d" — the "vs previous" line


# The windows the dashboard offers, in the order the picker shows them. The
# 24-hour view buckets by hour: a day-bucketed "last 24 hours" is one or two
# bars, which is a number pretending to be a chart.
RANGES = {
    "24h": Range(24, "hour", "24 hours", "24h"),
    "7": Range(7, "day", "7 days", "7d"),
    "28": Range(28, "day", "28 days", "28d"),
    "90": Range(90, "day", "90 days", "90d"),
}
DEFAULT_RANGE = "28"

_STEP = {"day": timedelta(days=1), "hour": timedelta(hours=1)}

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


def _utc_hour(col):  # noqa: ANN001, ANN202 — SQLAlchemy column expression
    """The UTC hour a timestamptz falls in, as a naive `datetime` (UTC)."""
    return func.date_trunc("hour", func.timezone("UTC", col))


async def _bucketed(
    db: AsyncSession, column, since: datetime, unit: str, *conds
) -> dict:  # noqa: ANN001
    """`{bucket: count}` for rows whose `column` falls on or after `since`.
    A bucket is a `date` for daily windows and a naive UTC `datetime` (top of
    the hour) for hourly ones — the same shapes `bucket_axis` produces."""
    bucket = _utc_hour(column) if unit == "hour" else _utc_day(column)
    rows = (
        await db.execute(
            select(bucket.label("b"), func.count())
            .where(column >= since, *conds)
            .group_by(bucket)
            .order_by(bucket)
        )
    ).all()
    return {r[0]: int(r[1]) for r in rows}


def _fill(buckets: dict, axis: list) -> list[int]:
    """A dense list aligned to `axis` — a bucket with no rows is a real zero,
    not a gap. A chart that skips empty days lies about the shape of the curve."""
    return [int(buckets.get(b, 0)) for b in axis]


def day_axis(days: int, today: date | None = None) -> list[date]:
    """The `days` calendar days ending today (inclusive), oldest first."""
    today = today or datetime.now(UTC).date()
    return [today - timedelta(days=n) for n in range(days - 1, -1, -1)]


def hour_axis(hours: int, now: datetime | None = None) -> list[datetime]:
    """The `hours` clock hours ending with the current one (inclusive), oldest
    first, as naive UTC datetimes — the shape `date_trunc('hour', …)` returns."""
    now = (now or datetime.now(UTC)).astimezone(UTC).replace(tzinfo=None)
    top = now.replace(minute=0, second=0, microsecond=0)
    return [top - timedelta(hours=n) for n in range(hours - 1, -1, -1)]


def bucket_axis(rng: Range, now: datetime | None = None) -> list:
    if rng.unit == "hour":
        return hour_axis(rng.buckets, now)
    return day_axis(rng.buckets, (now or datetime.now(UTC)).astimezone(UTC).date())


def bucket_start(bucket: date | datetime) -> datetime:
    """The aware UTC instant a bucket begins — midnight for a day, the top of the
    hour for an hour. `datetime` is checked first: it is a subclass of `date`."""
    if isinstance(bucket, datetime):
        return bucket.replace(tzinfo=UTC)
    return datetime(bucket.year, bucket.month, bucket.day, tzinfo=UTC)


def bucket_label(bucket: date | datetime) -> str:
    """A chart column's label. An hour is labelled on the clock the operators live
    by — its start in IST, so the 11:00 UTC hour reads "6 Oct, 16:30" — which is
    also what the list a click on that column opens calls it ("16:30–17:30 IST").
    A day is a UTC day and keeps its plain date: it is a window, not an instant."""
    if isinstance(bucket, datetime):
        return to_ist(bucket_start(bucket)).strftime("%-d %b, %H:%M")
    return bucket.strftime("%-d %b")


def window_start(range_key: str, now: datetime | None = None) -> datetime | None:
    """Where a named window begins, as an aware UTC instant — or None for "all".

    The drill-down lists use this rather than their own arithmetic so that the
    rows a click opens add up to the number that was clicked: "7 days" means the
    seven calendar days the trend card summed (today included), not "now minus
    168 hours", and "today" is the same UTC midnight the today tiles count from.
    """
    now = now or datetime.now(UTC)
    if range_key == "today":
        return bucket_start(now.astimezone(UTC).date())
    if range_key in RANGES:
        return bucket_start(bucket_axis(RANGES[range_key], now)[0])
    return None


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


async def growth(db: AsyncSession, range_key: str) -> dict:
    """Per-bucket arrivals over the chosen window, plus the same figure for the
    window before it so every KPI can carry a direction.

    Cached for 3 minutes (one minute for the hourly view, where three minutes is
    a twentieth of a bucket): it is ~8 grouped counts, and a growth curve that
    is three minutes stale is still the same curve.
    """
    ttl = 60 if RANGES[range_key].unit == "hour" else 180
    return await cache.get_or_compute(f"growth:{range_key}", ttl, lambda: _growth(db, range_key))


async def _growth(db: AsyncSession, range_key: str) -> dict:
    rng = RANGES[range_key]
    axis = bucket_axis(rng)
    first = bucket_start(axis[0])
    step = _STEP[rng.unit]
    # Two windows: the one shown, and the one immediately before it (same
    # length) which the deltas compare against.
    since = first - step * rng.buckets

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
        buckets = await _bucketed(db, column, since, rng.unit, *conds)
        series[key] = _fill(buckets, axis)
        totals[key] = sum(series[key])
        prev[key] = sum(v for b, v in buckets.items() if bucket_start(b) < first)

    return {
        "range": range_key,
        "unit": rng.unit,
        "label": rng.label,
        "short": rng.short,
        "axis": [bucket_start(b).isoformat() for b in axis],
        "labels": [bucket_label(b) for b in axis],
        "buckets": chart_buckets(axis, series, step),
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


def _iso(at: datetime) -> str:
    return at.astimezone(UTC).strftime("%Y-%m-%dT%H:%MZ")


def chart_buckets(axis: list, series: dict[str, list[int]], step: timedelta) -> list[dict]:
    """One clickable column per bucket on the growth chart: its window, and the
    charted series that moved most in it — the list a click on that column opens
    first. A quiet bucket opens new readers, the chart's own first series."""
    out = []
    for i, b in enumerate(axis):
        start = bucket_start(b)
        values = {key: series[key][i] for key, _, _ in SERIES}
        top = max(values, key=lambda k: values[k]) if any(values.values()) else SERIES[0][0]
        out.append({"from": _iso(start), "to": _iso(start + step), "kind": top})
    return out


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
    """Aggregate context for the live count — how many sittings, across how many
    different books, and how long the longest has been going.

    The panel itself still names nobody: it is on screen whenever the dashboard
    is, refreshing every twenty seconds, and a wall of names nobody asked to see
    is not what a glance at the front page is for. *Who* is reading *what* is one
    click away at /activity/now — a deliberate act that is written to the audit
    log (owner decision, 4 Oct 2026; see `routers/activity.py`).
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
