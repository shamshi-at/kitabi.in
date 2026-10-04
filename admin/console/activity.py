"""The rows behind the numbers — every count in the console, opened as a list.

A dashboard tile, a trend card, a column of the growth chart, a reader's
"Books tracked", a book's "Shelved by readers": each is a COUNT, and each now
opens the rows it counted. They all land on one page (`routers/activity.py`)
because they are all the same question asked with a different scope — *what
arrived, in this window, for this reader or this book* — and one set of
queries answering it means a list can never disagree with the number that
opened it.

A **kind** is one thing that can be listed (books shelved, sittings, reviews…).
A **scope** narrows it: a time window, one reader, or one book. Not every kind
makes sense in every scope — a reader's notes are listed on their account, not
as a site-wide feed — so each kind names the contexts it appears in.

Private kinds (`Kind.private`) are a reader's Layer-2 data: their shelf,
progress, notes, lending, connections. The console did not show these at all
until 4 Oct 2026, when the owner decided operators should be able to see a
reader's whole account — with every view written to the audit log. That second
half is enforced in the router, not left to the template: see
`routers/activity.py`.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import Select, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .models_ref import (
    ActiveReadingSession,
    ActivityLogEntry,
    Author,
    Connection,
    Edition,
    LendingRecord,
    LibraryEntry,
    LibraryEntryTag,
    PersonalTag,
    Profile,
    Rating,
    ReadingNote,
    ReadingSession,
    Review,
    Series,
    SyncOp,
    Work,
)

PAGE_SIZE = 50


@dataclass(frozen=True)
class Scope:
    """What a list is narrowed to. `start`/`end` are aware UTC instants (either
    may be open); `reader_id` and `work_id` pin it to one account or one book."""

    start: datetime | None = None
    end: datetime | None = None
    reader_id: uuid.UUID | None = None
    work_id: uuid.UUID | None = None

    @property
    def context(self) -> str:
        if self.reader_id is not None:
            return "reader"
        if self.work_id is not None:
            return "work"
        return "all"


@dataclass(frozen=True)
class Kind:
    key: str
    label: str
    private: bool
    contexts: tuple[str, ...]
    # "Reading now" is a state, not an arrival: a window does not narrow it.
    windowed: bool = True


ALL, READER, WORK = "all", "reader", "work"

KINDS: tuple[Kind, ...] = (
    Kind("readers", "New readers", False, (ALL,)),
    Kind("active", "Active readers", False, (ALL,)),
    Kind("now", "Reading now", True, (ALL, READER, WORK), windowed=False),
    Kind("shelved", "Books shelved", True, (ALL, READER, WORK)),
    Kind("finished", "Books finished", True, (ALL, READER, WORK)),
    Kind("sittings", "Reading sittings", True, (ALL, READER, WORK)),
    Kind("notes", "Notes", True, (READER,)),
    Kind("reviews", "Reviews", True, (ALL, READER, WORK)),
    Kind("ratings", "Ratings", True, (ALL, READER, WORK)),
    Kind("lending", "Lending", True, (READER,)),
    Kind("works", "Works added", False, (ALL, READER)),
    Kind("authors", "Authors added", False, (ALL, READER)),
    Kind("connections", "Connections", True, (READER,)),
    Kind("log", "Activity log", True, (READER,)),
)
BY_KEY = {k.key: k for k in KINDS}


def kinds_for(context: str) -> list[Kind]:
    return [k for k in KINDS if context in k.contexts]


# ---------------------------------------------------------------------------
# Statements. Each kind is one SELECT (rows) whose COUNT is the tab's number —
# the same statement both times, so a tab can never promise rows it won't show.
# ---------------------------------------------------------------------------


def _win(col, scope: Scope) -> list:  # noqa: ANN001 — SQLAlchemy column
    conds = []
    if scope.start is not None:
        conds.append(col >= scope.start)
    if scope.end is not None:
        conds.append(col < scope.end)
    return conds


def _win_date(col, scope: Scope) -> list:  # noqa: ANN001 — a plain DATE column
    """A window over a `date` column. `finish_date` is a calendar day the reader
    picked, with no time of day, so a window opening at 09:00 includes that
    whole day — the closest honest reading of "finished in the last 24 hours"."""
    conds = []
    if scope.start is not None:
        conds.append(col >= scope.start.astimezone(UTC).date())
    if scope.end is not None:
        conds.append(col < scope.end.astimezone(UTC).date())
    return conds


def _entry_book(stmt: Select, entry_id_col) -> Select:  # noqa: ANN001
    """Join a library-entry id through its edition to the work, for the title."""
    return (
        stmt.join(LibraryEntry, LibraryEntry.id == entry_id_col)
        .join(Edition, Edition.id == LibraryEntry.edition_id)
        .join(Work, Work.id == Edition.work_id)
    )


def _statement(kind: str, scope: Scope) -> tuple[Select, tuple]:  # noqa: C901, PLR0911, PLR0912
    """(row select, its ORDER BY) for one kind under one scope."""
    r, w = scope.reader_id, scope.work_id

    if kind == "readers":
        stmt = select(Profile).where(Profile.deleted_at.is_(None), *_win(Profile.created_at, scope))
        return stmt, (Profile.created_at.desc(),)

    if kind == "active":
        last = func.max(SyncOp.applied_at).label("last")
        stmt = (
            select(SyncOp.user_id, last, func.count().label("n"))
            .where(*_win(SyncOp.applied_at, scope))
            .group_by(SyncOp.user_id)
        )
        return stmt, (last.desc(),)

    if kind == "now":
        stmt = (
            select(ActiveReadingSession, Work.id, Work.title)
            .outerjoin(LibraryEntry, LibraryEntry.id == ActiveReadingSession.library_entry_id)
            .outerjoin(Edition, Edition.id == LibraryEntry.edition_id)
            .outerjoin(Work, Work.id == Edition.work_id)
        )
        if r is not None:
            stmt = stmt.where(ActiveReadingSession.user_id == r)
        if w is not None:
            stmt = stmt.where(Work.id == w)
        # Longest-running first: a sitting nobody stopped is the one to look at.
        return stmt, (ActiveReadingSession.started_at.asc(),)

    if kind in ("shelved", "finished"):
        stmt = (
            select(LibraryEntry, Edition, Work.id, Work.title)
            .join(Edition, Edition.id == LibraryEntry.edition_id)
            .join(Work, Work.id == Edition.work_id)
            .where(LibraryEntry.deleted_at.is_(None))
        )
        if kind == "finished":
            stmt = stmt.where(
                LibraryEntry.status == "read", *_win_date(LibraryEntry.finish_date, scope)
            )
            order = (
                LibraryEntry.finish_date.desc().nulls_last(),
                LibraryEntry.updated_at.desc(),
            )
        else:
            stmt = stmt.where(*_win(LibraryEntry.created_at, scope))
            order = (LibraryEntry.created_at.desc(),)
        if r is not None:
            stmt = stmt.where(LibraryEntry.user_id == r)
        if w is not None:
            stmt = stmt.where(Edition.work_id == w)
        return stmt, order

    if kind == "sittings":
        stmt = _entry_book(
            select(ReadingSession, Work.id, Work.title), ReadingSession.library_entry_id
        ).where(ReadingSession.deleted_at.is_(None), *_win(ReadingSession.started_at, scope))
        if r is not None:
            stmt = stmt.where(ReadingSession.user_id == r)
        if w is not None:
            stmt = stmt.where(Work.id == w)
        return stmt, (ReadingSession.started_at.desc(),)

    if kind == "notes":
        stmt = _entry_book(
            select(ReadingNote, Work.id, Work.title), ReadingNote.library_entry_id
        ).where(ReadingNote.deleted_at.is_(None), *_win(ReadingNote.created_at, scope))
        if r is not None:
            stmt = stmt.where(ReadingNote.user_id == r)
        if w is not None:
            stmt = stmt.where(Work.id == w)
        return stmt, (ReadingNote.created_at.desc(),)

    if kind in ("reviews", "ratings"):
        model = Review if kind == "reviews" else Rating
        stmt = (
            select(model, Work.id, Work.title, Series.id, Series.name)
            .outerjoin(Work, Work.id == model.work_id)
            .outerjoin(Series, Series.id == model.series_id)
            .where(model.deleted_at.is_(None), *_win(model.created_at, scope))
        )
        if r is not None:
            stmt = stmt.where(model.user_id == r)
        if w is not None:
            stmt = stmt.where(model.work_id == w)
        return stmt, (model.created_at.desc(),)

    if kind == "lending":
        # A loan names its book through its library entry, or — on older
        # borrowed rows — through `edition_id` alone (see LendingRecord).
        stmt = (
            select(LendingRecord, Work.id, Work.title)
            .outerjoin(LibraryEntry, LibraryEntry.id == LendingRecord.library_entry_id)
            .outerjoin(
                Edition,
                Edition.id == func.coalesce(LendingRecord.edition_id, LibraryEntry.edition_id),
            )
            .outerjoin(Work, Work.id == Edition.work_id)
            .where(LendingRecord.deleted_at.is_(None), *_win(LendingRecord.created_at, scope))
        )
        if r is not None:
            stmt = stmt.where(LendingRecord.user_id == r)
        if w is not None:
            stmt = stmt.where(Work.id == w)
        return stmt, (LendingRecord.lent_date.desc(), LendingRecord.created_at.desc())

    if kind == "works":
        stmt = (
            select(Work)
            .options(selectinload(Work.authors))
            .where(Work.deleted_at.is_(None), *_win(Work.created_at, scope))
        )
        if r is not None:
            stmt = stmt.where(Work.created_by_user_id == r)
        return stmt, (Work.created_at.desc(),)

    if kind == "authors":
        stmt = select(Author).where(Author.deleted_at.is_(None), *_win(Author.created_at, scope))
        if r is not None:
            stmt = stmt.where(Author.created_by_user_id == r)
        return stmt, (Author.created_at.desc(),)

    if kind == "connections":
        stmt = select(Connection).where(*_win(Connection.created_at, scope))
        if r is not None:
            stmt = stmt.where(or_(Connection.requester_id == r, Connection.addressee_id == r))
        return stmt, (Connection.created_at.desc(),)

    if kind == "log":
        stmt = select(ActivityLogEntry).where(
            ActivityLogEntry.deleted_at.is_(None), *_win(ActivityLogEntry.occurred_at, scope)
        )
        if r is not None:
            stmt = stmt.where(ActivityLogEntry.user_id == r)
        return stmt, (ActivityLogEntry.occurred_at.desc(),)

    raise KeyError(kind)


def _scoped(kind: Kind, scope: Scope) -> Scope:
    """The scope a kind is actually counted under — a windowless kind drops the
    window but keeps the reader/book."""
    if kind.windowed:
        return scope
    return Scope(reader_id=scope.reader_id, work_id=scope.work_id)


async def count(db: AsyncSession, kind: str, scope: Scope) -> int:
    stmt, _ = _statement(kind, _scoped(BY_KEY[kind], scope))
    return int(await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0)


async def counts(db: AsyncSession, scope: Scope) -> dict[str, int]:
    """Every kind that belongs in this scope's context, counted — the tab strip."""
    return {k.key: await count(db, k.key, scope) for k in kinds_for(scope.context)}


async def minutes(db: AsyncSession, scope: Scope) -> int:
    """Total reading time of the sittings in scope — what "Minutes read today"
    on the dashboard is the sum of."""
    stmt, _ = _statement("sittings", scope)
    total = await db.scalar(select(func.coalesce(func.sum(stmt.subquery().c.duration_seconds), 0)))
    return round(int(total or 0) / 60)


# ---------------------------------------------------------------------------
# Rows. Plain dicts, so the template reads one shape per kind and a missing
# reader (a deleted account) is a None it can render, not an exception.
# ---------------------------------------------------------------------------


async def _profiles(db: AsyncSession, ids) -> dict[uuid.UUID, Profile]:  # noqa: ANN001
    wanted = {i for i in ids if i is not None}
    if not wanted:
        return {}
    found = (await db.execute(select(Profile).where(Profile.id.in_(wanted)))).scalars().all()
    return {p.id: p for p in found}


async def _tags(db: AsyncSession, entry_ids: list[uuid.UUID]) -> dict[uuid.UUID, list[str]]:
    if not entry_ids:
        return {}
    pairs = (
        await db.execute(
            select(LibraryEntryTag.library_entry_id, PersonalTag.name)
            .join(PersonalTag, PersonalTag.id == LibraryEntryTag.tag_id)
            .where(
                LibraryEntryTag.library_entry_id.in_(entry_ids),
                LibraryEntryTag.deleted_at.is_(None),
                PersonalTag.deleted_at.is_(None),
            )
            .order_by(PersonalTag.name)
        )
    ).all()
    out: dict[uuid.UUID, list[str]] = {}
    for entry_id, name in pairs:
        out.setdefault(entry_id, []).append(name)
    return out


def _payload(data: dict | None) -> str:
    if not data:
        return ""
    text = json.dumps(data, ensure_ascii=False, default=str, separators=(", ", ": "))
    return text if len(text) <= 160 else text[:157] + "…"


def running_minutes(started: datetime, now: datetime | None = None) -> int:
    now = now or datetime.now(UTC)
    if started.tzinfo is None:
        started = started.replace(tzinfo=UTC)
    return max(0, round((now - started).total_seconds() / 60))


async def rows(  # noqa: C901, PLR0912
    db: AsyncSession, kind: str, scope: Scope, page: int = 1, size: int = PAGE_SIZE
) -> tuple[list[dict], bool]:
    """One page of rows, newest first, and whether another page follows.

    Fetches `size + 1` to answer "is there more?" without a second COUNT."""
    stmt, order = _statement(kind, _scoped(BY_KEY[kind], scope))
    raw = (await db.execute(stmt.order_by(*order).offset((page - 1) * size).limit(size + 1))).all()
    more = len(raw) > size
    raw = raw[:size]

    out: list[dict] = []
    if kind == "readers":
        out = [{"reader_id": p.id, "reader": p, "at": p.created_at} for (p,) in raw]

    elif kind == "active":
        people = await _profiles(db, (uid for uid, _, _ in raw))
        out = [
            {"reader_id": uid, "reader": people.get(uid), "at": last, "ops": int(n)}
            for uid, last, n in raw
        ]

    elif kind == "now":
        people = await _profiles(db, (s.user_id for s, _, _ in raw))
        now = datetime.now(UTC)
        out = [
            {
                "reader_id": s.user_id,
                "reader": people.get(s.user_id),
                "work_id": wid,
                "title": title,
                "s": s,
                "minutes": running_minutes(s.started_at, now),
                "at": s.started_at,
            }
            for s, wid, title in raw
        ]

    elif kind in ("shelved", "finished"):
        people = await _profiles(db, (e.user_id for e, _, _, _ in raw))
        tags = await _tags(db, [e.id for e, _, _, _ in raw])
        out = [
            {
                "reader_id": e.user_id,
                "reader": people.get(e.user_id),
                "work_id": wid,
                "title": title,
                "e": e,
                "edition": ed,
                "tags": tags.get(e.id, []),
                "at": e.created_at,
            }
            for e, ed, wid, title in raw
        ]

    elif kind in ("sittings", "notes"):
        people = await _profiles(db, (x.user_id for x, _, _ in raw))
        out = [
            {
                "reader_id": x.user_id,
                "reader": people.get(x.user_id),
                "work_id": wid,
                "title": title,
                "x": x,
                "minutes": round(x.duration_seconds / 60) if kind == "sittings" else None,
                "at": x.started_at if kind == "sittings" else x.created_at,
            }
            for x, wid, title in raw
        ]

    elif kind in ("reviews", "ratings"):
        people = await _profiles(db, (x.user_id for x, *_ in raw))
        for x, wid, title, sid, sname in raw:
            if wid is not None:
                subject = {"kind": "works", "id": wid, "name": title}
            elif sid is not None:
                subject = {"kind": "series", "id": sid, "name": sname}
            else:
                subject = None
            out.append(
                {
                    "reader_id": x.user_id,
                    "reader": people.get(x.user_id),
                    "work_id": wid,
                    "title": title,
                    "subject": subject,
                    "x": x,
                    "at": x.created_at,
                }
            )

    elif kind == "lending":
        ids = [x.user_id for x, _, _ in raw] + [x.borrower_user_id for x, _, _ in raw]
        people = await _profiles(db, ids)
        out = [
            {
                "reader_id": x.user_id,
                "reader": people.get(x.user_id),
                "work_id": wid,
                "title": title,
                "x": x,
                "other": people.get(x.borrower_user_id) if x.borrower_user_id else None,
                "at": x.created_at,
            }
            for x, wid, title in raw
        ]

    elif kind in ("works", "authors"):
        people = await _profiles(db, (x.created_by_user_id for (x,) in raw))
        out = [
            {
                "x": x,
                "adder_id": x.created_by_user_id,
                "adder": people.get(x.created_by_user_id) if x.created_by_user_id else None,
                "at": x.created_at,
            }
            for (x,) in raw
        ]

    elif kind == "connections":
        mine = scope.reader_id

        def other(c: Connection) -> uuid.UUID:
            if mine is None:
                return c.addressee_id
            return c.addressee_id if c.requester_id == mine else c.requester_id

        people = await _profiles(
            db, [c.requester_id for (c,) in raw] + [c.addressee_id for (c,) in raw]
        )
        out = [
            {
                "x": c,
                "reader_id": c.requester_id,
                "reader": people.get(c.requester_id),
                "other_id": other(c),
                "other": people.get(other(c)),
                "sent": mine is not None and c.requester_id == mine,
                "at": c.created_at,
            }
            for (c,) in raw
        ]

    elif kind == "log":
        people = await _profiles(db, (x.user_id for (x,) in raw))
        out = [
            {
                "reader_id": x.user_id,
                "reader": people.get(x.user_id),
                "x": x,
                "payload": _payload(x.payload),
                "at": x.occurred_at,
            }
            for (x,) in raw
        ]

    return out, more
