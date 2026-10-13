"""Your circle — what a reader's accepted connections have read, rated and own,
as far as each of them agreed to show it (docs/circle-reading-mockups.html).

Every rule that decides who may be seen lives in this file, and every endpoint
goes through `_people_for_works`, so there is one answer to "may the caller see
this person on this book?":

1. Only **accepted** connections — pending, denied and blocked rows never count.
2. Only what the person switched on: `circle_share_reading` (status, finished
   dates, read count, public review quote), `circle_share_ratings` (their stars
   — and only alongside reading, so a rating is never shown detached from the
   read it judges), `circle_share_owned` (they have a copy; borrow requests).
3. Never a book they kept to themselves: one hidden entry for a work hides the
   person on that work entirely, whatever else they hold of it.
4. Reviews keep their own flag — only `visible` ones are quoted.
5. Counts only count people who appear; there is no "and 2 who hid it".
6. Reciprocity: a caller who shares nothing gets an `invite` count (how many of
   their connections share) instead of anyone's reading.

Queries select plain columns, never whole catalogue rows — the egress lesson of
7 Sep 2026 (CLAUDE.md). Nothing here is cached server-side: `ttl_cache` is for
anonymous values only, and these answers are per reader.
"""

from __future__ import annotations

import hashlib
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.borrow_request import BorrowRequest
from app.models.connection import Connection
from app.models.edition import Edition
from app.models.library_entry import LibraryEntry
from app.models.profile import Profile
from app.models.publisher import Publisher
from app.models.rating import Rating
from app.models.read import Read
from app.models.review import Review
from app.models.work import Work
from app.schemas.circle import (
    CirclePersonOut,
    CircleSignalOut,
    CircleTranslationOut,
    CircleWorkOut,
)

# How far back Home looks for something worth mentioning.
RECENT_DAYS = 60
READ_ALONG_DAYS = 30
# Faces per bucket on a search row — the line names two and says "& N more".
SIGNAL_FACES = 3
REVIEW_QUOTE_CHARS = 280


def shares_anything(profile: Profile) -> bool:
    """Ratings ride on reading, so sharing ratings alone shares nothing."""
    return bool(profile.circle_share_reading or profile.circle_share_owned)


def display_name(profile: Profile) -> str:
    return profile.full_name or (f"@{profile.username}" if profile.username else "A connection")


async def accepted_ids(db: AsyncSession, me: uuid.UUID) -> set[uuid.UUID]:
    rows = await db.execute(
        select(Connection.requester_id, Connection.addressee_id).where(
            Connection.status == "accepted",
            or_(Connection.requester_id == me, Connection.addressee_id == me),
        )
    )
    return {b if a == me else a for a, b in rows.all()}


async def sharers(db: AsyncSession, me: uuid.UUID) -> dict[uuid.UUID, Profile]:
    """The caller's accepted connections who share something, keyed by id."""
    ids = await accepted_ids(db, me)
    if not ids:
        return {}
    found = await db.execute(
        select(Profile).where(
            Profile.id.in_(ids),
            Profile.deleted_at.is_(None),
            Profile.suspended_at.is_(None),
            or_(Profile.circle_share_reading.is_(True), Profile.circle_share_owned.is_(True)),
        )
    )
    return {p.id: p for p in found.scalars().all()}


@dataclass
class _Pair:
    """Everything one person holds of one work, before the rules are applied."""

    statuses: set[str] = field(default_factory=set)
    entry_ids: list[uuid.UUID] = field(default_factory=list)
    hidden: bool = False
    finished_on: date | None = None
    started_on: date | None = None
    owned_edition_id: uuid.UUID | None = None
    owned_edition_label: str | None = None


def _edition_label(publisher: str | None, pub_date: date | None) -> str | None:
    parts = [p for p in (publisher, str(pub_date.year) if pub_date else None) if p]
    return ", ".join(parts) or None


def _latest(a: date | None, b: date | None) -> date | None:
    if a is None:
        return b
    if b is None:
        return a
    return max(a, b)


async def _people_for_works(
    db: AsyncSession, people: dict[uuid.UUID, Profile], work_ids: set[uuid.UUID]
) -> dict[uuid.UUID, list[CirclePersonOut]]:
    """Per work, every sharer the caller may see on it — the single gate."""
    if not people or not work_ids:
        return {}
    rows = await db.execute(
        select(
            LibraryEntry.id,
            LibraryEntry.user_id,
            LibraryEntry.status,
            LibraryEntry.ownership,
            LibraryEntry.start_date,
            LibraryEntry.finish_date,
            LibraryEntry.circle_hidden,
            Edition.work_id,
            Edition.id,
            Edition.pub_date,
            Publisher.name,
        )
        .join(Edition, Edition.id == LibraryEntry.edition_id)
        .outerjoin(Publisher, Publisher.id == Edition.publisher_id)
        .where(
            LibraryEntry.user_id.in_(people.keys()),
            LibraryEntry.deleted_at.is_(None),
            Edition.work_id.in_(work_ids),
        )
    )
    pairs: dict[tuple[uuid.UUID, uuid.UUID], _Pair] = defaultdict(_Pair)
    for (
        entry_id,
        user_id,
        status,
        ownership,
        start,
        finish,
        hidden,
        work_id,
        edition_id,
        pub_date,
        publisher,
    ) in rows.all():
        pair = pairs[(user_id, work_id)]
        pair.hidden = pair.hidden or hidden
        pair.statuses.add(status)
        pair.entry_ids.append(entry_id)
        if status == "read":
            pair.finished_on = _latest(pair.finished_on, finish)
        if status == "reading":
            pair.started_on = _latest(pair.started_on, start)
        if ownership == "owned" and status != "wishlist" and pair.owned_edition_id is None:
            pair.owned_edition_id = edition_id
            pair.owned_edition_label = _edition_label(publisher, pub_date)

    pairs = {k: v for k, v in pairs.items() if not v.hidden}
    if not pairs:
        return {}

    entry_ids = [e for p in pairs.values() for e in p.entry_ids]
    finished: dict[uuid.UUID, tuple[int, date | None]] = {}
    read_rows = await db.execute(
        select(Read.library_entry_id, func.count(), func.max(Read.finish_date))
        .where(
            Read.library_entry_id.in_(entry_ids),
            Read.status == "read",
            Read.deleted_at.is_(None),
        )
        .group_by(Read.library_entry_id)
    )
    for entry_id, count, last in read_rows.all():
        finished[entry_id] = (count, last)

    reading_users = {u for u, p in people.items() if p.circle_share_reading}
    rating_users = {u for u in reading_users if people[u].circle_share_ratings}
    ratings: dict[tuple[uuid.UUID, uuid.UUID], int] = {}
    if rating_users:
        rating_rows = await db.execute(
            select(Rating.user_id, Rating.work_id, Rating.value).where(
                Rating.user_id.in_(rating_users),
                Rating.work_id.in_(work_ids),
                Rating.deleted_at.is_(None),
            )
        )
        ratings = {(u, w): v for u, w, v in rating_rows.all()}
    reviews: dict[tuple[uuid.UUID, uuid.UUID], str] = {}
    if reading_users:
        review_rows = await db.execute(
            select(Review.user_id, Review.work_id, Review.body)
            .where(
                Review.user_id.in_(reading_users),
                Review.work_id.in_(work_ids),
                Review.visible.is_(True),
                Review.deleted_at.is_(None),
            )
            .order_by(Review.created_at)
        )
        reviews = {(u, w): body for u, w, body in review_rows.all()}

    out: dict[uuid.UUID, list[CirclePersonOut]] = defaultdict(list)
    for (user_id, work_id), pair in pairs.items():
        profile = people[user_id]
        status: str | None = None
        read_count = 0
        finished_on = pair.finished_on
        if profile.circle_share_reading:
            for e in pair.entry_ids:
                count, last = finished.get(e, (0, None))
                read_count += count
                finished_on = _latest(finished_on, last)
            if "reading" in pair.statuses:
                status = "reading"
            elif "read" in pair.statuses or read_count:
                status = "read"
                read_count = max(read_count, 1)
        owns = profile.circle_share_owned and pair.owned_edition_id is not None
        if status is None and not owns:
            continue
        quote = reviews.get((user_id, work_id)) if status else None
        if quote and len(quote) > REVIEW_QUOTE_CHARS:
            quote = quote[: REVIEW_QUOTE_CHARS - 1].rstrip() + "…"
        out[work_id].append(
            CirclePersonOut(
                user_id=user_id,
                name=display_name(profile),
                avatar_url=profile.avatar_url,
                status=status,
                read_count=read_count if status else 0,
                finished_on=finished_on if status == "read" else None,
                started_on=pair.started_on if status == "reading" else None,
                rating=ratings.get((user_id, work_id)) if status else None,
                review=quote,
                owns=owns,
                owned_edition_id=pair.owned_edition_id if owns else None,
                owned_edition_label=pair.owned_edition_label if owns else None,
            )
        )
    for persons in out.values():
        persons.sort(key=_recency, reverse=True)
    return out


def _recency(p: CirclePersonOut) -> tuple[date, str]:
    when = p.finished_on or p.started_on or date.min
    return (when, p.name)


def _avg(persons: list[CirclePersonOut]) -> float | None:
    stars = [p.rating for p in persons if p.rating is not None]
    return round(sum(stars) / len(stars), 1) if stars else None


def summarize(persons: list[CirclePersonOut]) -> CircleSignalOut:
    readers = [p for p in persons if p.status == "read"]
    reading = [p for p in persons if p.status == "reading"]
    owners = [p for p in persons if p.owns]
    return CircleSignalOut(
        read_count=len(readers),
        reading_count=len(reading),
        owns_count=len(owners),
        readers=readers[:SIGNAL_FACES],
        reading=reading[:SIGNAL_FACES],
        owners=owners[:SIGNAL_FACES],
        avg_rating=_avg(persons),
    )


async def holdings(db: AsyncSession, me: uuid.UUID, work_ids: set[uuid.UUID]) -> set[uuid.UUID]:
    """The books the caller already has — on any shelf but Wishlist, in any
    printing (reading, read, to read, stopped, owned or borrowed). Nobody asks
    to borrow those (owner request, 14 Oct 2026); a wish is exactly what an
    ask is for."""
    if not work_ids:
        return set()
    rows = await db.execute(
        select(Edition.work_id)
        .select_from(LibraryEntry)
        .join(Edition, Edition.id == LibraryEntry.edition_id)
        .where(
            LibraryEntry.user_id == me,
            LibraryEntry.deleted_at.is_(None),
            LibraryEntry.status != "wishlist",
            Edition.work_id.in_(work_ids),
        )
        .distinct()
    )
    return set(rows.scalars().all())


async def _mark_asked(
    db: AsyncSession, me: uuid.UUID, by_work: dict[uuid.UUID, list[CirclePersonOut]]
) -> None:
    """Flag each owner the caller has an open ask with for that book, so every
    surface says "Requested" rather than offering to ask again — whichever
    screen the ask was made from (owner request, 14 Oct 2026). Matched on the
    work, like the ask itself is closed on the work."""
    owners = {p.user_id for persons in by_work.values() for p in persons if p.owns}
    if not owners:
        return
    rows = await db.execute(
        select(BorrowRequest.owner_id, Edition.work_id)
        .join(Edition, Edition.id == BorrowRequest.edition_id)
        .where(
            BorrowRequest.requester_id == me,
            BorrowRequest.status == "open",
            BorrowRequest.owner_id.in_(owners),
            Edition.work_id.in_(by_work.keys()),
        )
    )
    asked = set(rows.all())
    for work_id, persons in by_work.items():
        for p in persons:
            if (p.user_id, work_id) in asked:
                p.asked = True


async def signals(
    db: AsyncSession,
    me: uuid.UUID,
    people: dict[uuid.UUID, Profile],
    work_ids: list[uuid.UUID],
) -> dict[str, CircleSignalOut]:
    """One search page's worth of one-line summaries, in one round trip. Works
    with nothing to say are left out rather than sent as zeros."""
    by_work = await _people_for_works(db, people, set(work_ids))
    await _mark_asked(db, me, by_work)
    held = await holdings(db, me, set(by_work))
    out = {}
    for w, persons in by_work.items():
        if persons:
            summary = summarize(persons)
            summary.can_ask = w not in held
            out[str(w)] = summary
    return out


async def for_work(
    db: AsyncSession, me: uuid.UUID, people: dict[uuid.UUID, Profile], work_id: uuid.UUID
) -> CircleWorkOut:
    by_work = await _people_for_works(db, people, {work_id})
    await _mark_asked(db, me, by_work)
    persons = by_work.get(work_id, [])
    summary = summarize(persons)
    out = CircleWorkOut(
        people=persons,
        read_count=summary.read_count,
        reading_count=summary.reading_count,
        owns_count=summary.owns_count,
        avg_rating=summary.avg_rating,
        can_ask=work_id not in await holdings(db, me, {work_id}),
    )
    group_id = (
        await db.execute(select(Work.translation_group_id).where(Work.id == work_id))
    ).scalar_one_or_none()
    if group_id is not None:
        siblings = (
            await db.execute(
                select(Work.id, Work.title, Work.language).where(
                    Work.translation_group_id == group_id,
                    Work.id != work_id,
                    Work.deleted_at.is_(None),
                    Work.merged_into_id.is_(None),
                )
            )
        ).all()
        if siblings:
            by_work = await _people_for_works(db, people, {s.id for s in siblings})
            first_edition: dict[uuid.UUID, uuid.UUID] = {}
            edition_rows = await db.execute(
                select(Edition.work_id, Edition.id)
                .where(
                    Edition.work_id.in_([s.id for s in siblings]),
                    Edition.deleted_at.is_(None),
                )
                .order_by(Edition.created_at)
            )
            for sib_id, edition_id in edition_rows.all():
                first_edition.setdefault(sib_id, edition_id)
            for sib in siblings:
                readers = [p for p in by_work.get(sib.id, []) if p.status == "read"]
                if readers:
                    out.translations.append(
                        CircleTranslationOut(
                            work_id=sib.id,
                            edition_id=first_edition.get(sib.id),
                            title=sib.title,
                            language=sib.language,
                            read_count=len(readers),
                            names=[p.name for p in readers[:2]],
                        )
                    )
    return out


# ---------------------------------------------------------------- Home's pick


@dataclass
class Pick:
    kind: str
    work_id: uuid.UUID
    person: CirclePersonOut | None = None
    people: list[CirclePersonOut] = field(default_factory=list)
    also_read_count: int = 0
    my_rating: int | None = None


def _day_order(me: uuid.UUID, today: date, work_id: uuid.UUID) -> str:
    """Stable for a day, different tomorrow — the card doesn't reshuffle every
    time Home opens, and doesn't show the same book every day either."""
    return hashlib.sha256(f"{me}:{today.isoformat()}:{work_id}".encode()).hexdigest()


async def pick(
    db: AsyncSession,
    me: uuid.UUID,
    people: dict[uuid.UUID, Profile],
    dismissed: set[uuid.UUID],
    today: date | None = None,
) -> Pick | None:
    """At most one card. In order of preference: a wishlist book a connection
    owns (borrow, Kitabi's wedge) › a to-read book a connection just started
    (read along) › a book a connection finished recently and loved › a book
    several finished recently › a book you both loved (kindred — warmth, never
    a sale)."""
    if not people:
        return None
    today = today or datetime.now(UTC).date()
    recent = today - timedelta(days=RECENT_DAYS)
    along = today - timedelta(days=READ_ALONG_DAYS)

    mine = await db.execute(
        select(Edition.work_id, LibraryEntry.status)
        .select_from(LibraryEntry)
        .join(Edition, Edition.id == LibraryEntry.edition_id)
        .where(LibraryEntry.user_id == me, LibraryEntry.deleted_at.is_(None))
    )
    my_statuses: dict[uuid.UUID, set[str]] = defaultdict(set)
    for work_id, status in mine.all():
        my_statuses[work_id].add(status)
    # A book wished for in one printing but already held in another is held.
    held = {w for w, s in my_statuses.items() if s - {"wishlist"}}
    wishlist = {w for w, s in my_statuses.items() if "wishlist" in s} - held
    to_read = {w for w, s in my_statuses.items() if "pending" in s}

    my_ratings = dict(
        (
            await db.execute(
                select(Rating.work_id, Rating.value).where(
                    Rating.user_id == me,
                    Rating.work_id.is_not(None),
                    Rating.deleted_at.is_(None),
                )
            )
        ).all()
    )

    readers = [u for u, p in people.items() if p.circle_share_reading]
    raters = [u for u in readers if people[u].circle_share_ratings]

    recent_finished: set[uuid.UUID] = set()
    if readers:
        recent_finished = set(
            (
                await db.execute(
                    select(Edition.work_id)
                    .select_from(LibraryEntry)
                    .join(Edition, Edition.id == LibraryEntry.edition_id)
                    .where(
                        LibraryEntry.user_id.in_(readers),
                        LibraryEntry.deleted_at.is_(None),
                        LibraryEntry.status == "read",
                        LibraryEntry.finish_date >= recent,
                    )
                    .distinct()
                    .limit(300)
                )
            )
            .scalars()
            .all()
        ) - set(my_statuses)

    loved_by_me = {w for w, v in my_ratings.items() if v >= 4}
    kindred_candidates: set[uuid.UUID] = set()
    if raters and loved_by_me:
        kindred_candidates = set(
            (
                await db.execute(
                    select(Rating.work_id)
                    .where(
                        Rating.user_id.in_(raters),
                        Rating.work_id.in_(loved_by_me),
                        Rating.deleted_at.is_(None),
                        Rating.updated_at >= datetime.combine(recent, datetime.min.time(), UTC),
                    )
                    .distinct()
                )
            )
            .scalars()
            .all()
        )

    candidates = (wishlist | to_read | recent_finished | kindred_candidates) - dismissed
    if not candidates:
        return None
    by_work = await _people_for_works(db, people, candidates)
    await _mark_asked(db, me, by_work)

    def ordered(ids: set[uuid.UUID]) -> list[uuid.UUID]:
        return sorted(ids, key=lambda w: _day_order(me, today, w))

    for w in ordered(wishlist & candidates):
        owners = [p for p in by_work.get(w, []) if p.owns]
        if owners:
            return Pick("borrow", w, person=owners[0])

    for w in ordered(to_read & candidates):
        starters = [
            p
            for p in by_work.get(w, [])
            if p.status == "reading" and p.started_on is not None and p.started_on >= along
        ]
        if starters:
            return Pick("read_along", w, person=starters[0])

    def finished_recently(w: uuid.UUID) -> list[CirclePersonOut]:
        return [
            p
            for p in by_work.get(w, [])
            if p.status == "read" and p.finished_on is not None and p.finished_on >= recent
        ]

    fresh = recent_finished & candidates
    for w in ordered(fresh):
        loved = [p for p in finished_recently(w) if (p.rating or 0) >= 4]
        if loved:
            readers_of_w = [p for p in by_work.get(w, []) if p.status == "read"]
            return Pick("loved", w, person=loved[0], also_read_count=len(readers_of_w) - 1)

    for w in ordered(fresh):
        group = finished_recently(w)
        if len(group) >= 2:
            return Pick("cluster", w, people=group)

    for w in ordered(kindred_candidates & candidates):
        mine_value = my_ratings.get(w)
        agree = [p for p in by_work.get(w, []) if p.rating is not None and p.rating == mine_value]
        if agree:
            return Pick("kindred", w, person=agree[0], my_rating=mine_value)
    return None


def parse_dismissed(raw: str | None) -> set[uuid.UUID]:
    """`?dismissed=<id>,<id>` — junk is ignored rather than a 422, so a stale
    client list never costs the reader their card."""
    out: set[uuid.UUID] = set()
    for part in (raw or "").split(",")[:200]:
        try:
            out.add(uuid.UUID(part.strip()))
        except ValueError:
            continue
    return out


__all__ = [
    "Pick",
    "accepted_ids",
    "display_name",
    "for_work",
    "parse_dismissed",
    "pick",
    "sharers",
    "shares_anything",
    "signals",
    "summarize",
]
