"""Record candidates, and promote the complete ones into the catalogue.

Two functions, and the split between them is the safety property (owner,
9 Sep 2026: *"I don't want any unwanted records to be created"*):

- `record` writes to `catalog_intake` and **nothing else**. A source adapter
  can be run, re-run, fixed and re-run again without a single catalogue row
  appearing. Discovery is not a write to the catalogue.
- `promote` is the only function in the codebase that turns a candidate into a
  book, it only ever reads rows the gate already passed, and it creates each
  one through `catalog_service.create_work_with_edition` — the same path the
  app's add-book form uses.

Going through `catalog_service` rather than bulk SQL is deliberate and is the
difference between this and `etl/04_load.sql`. That script `COPY`s, which
bypasses the ORM, which is why `etl/06_backfill_script.py` has to come along
afterwards and recompute every transliteration column. Promotion instead
inherits, for free and already tested: `title_translit`/`title_fold` from the
`before_insert` hooks (so cross-script search works the moment the row lands),
`ensure_slug` (so the public page has its canonical URL immediately, rather
than waiting for `backfill_slugs` and moving under a crawler), publisher
resolution through `merge_service.canonical` (so a house an admin merged last
month is not re-created tonight — the 4 Sep 2026 lesson), and the ISBN
conflict guard.

That last one does double duty here. `create_work_with_edition` already
refuses an ISBN the catalogue holds, and the 409 it raises *names the work it
found*. So duplicate detection is not reimplemented — it is that refusal,
caught and recorded.

**A book is published with a cover we own, or it waits** (P2, 3 Oct 2026).
`promote` hands each candidate's cover to `cover_ingest` — fetched, shrunk to
~50 KB and stored in our R2 bucket — *before* the Work exists, and the edition
is created pointing at that copy. The alternative, publishing with the
source's URL and bringing the image home afterwards, is how the first seed
worked (`jobs/backfill_covers`), and it means a book can be live with a cover
that 404s. A candidate whose cover turns out to be unusable goes back to
`incomplete` and remembers which URL it was, so the nightly re-crawl offering
the same dead link does not walk it straight back into the queue.
"""

from __future__ import annotations

import logging
import re
import uuid
from collections.abc import Iterable, Sequence
from dataclasses import replace
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import Row, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import Author, CatalogIntake
from app.models.catalog_intake import (
    STATE_COMPLETE,
    STATE_DUPLICATE,
    STATE_INCOMPLETE,
    STATE_PROMOTED,
    STATE_REJECTED,
)
from app.models.edition import Edition
from app.models.work import Work, work_authors, work_translators
from app.schemas.catalog import EditionCreate, WorkCreate
from app.services import catalog_service, cover_ingest, intake_gate
from app.services import isbn as isbn_util
from app.services.intake_gate import Candidate
from app.services.translit import fold

logger = logging.getLogger(__name__)

#: Promotion attempts on one row before it stops being retried. A row that
#: keeps failing on something transient must not sit at the head of the queue
#: consuming the daily budget forever — the same reasoning as the sync queue's
#: five attempts, and the same outcome: it stops and becomes visible.
MAX_ATTEMPTS = 3

#: Consecutive "could not fetch the cover right now" outcomes that end a
#: promotion run early. A run of them is a source that is down or throttling
#: us, and pushing on would charge every remaining row an attempt for an
#: outage that is not its fault — `backfill_covers` backs off the same way.
MAX_CONSECUTIVE_COVER_FAILURES = 5

#: Consecutive rows that failed in a way nobody planned for before a promotion
#: run gives up. One such row is that row's problem and the run goes on; five
#: in a row is tonight's problem — the database, a deploy mid-run — and the
#: rest of the batch should not each be charged an attempt for it.
MAX_CONSECUTIVE_ERRORS = 5

#: Written on a candidate whose ISBN belongs to a book that was in the
#: catalogue and was taken out — undone with `revert`, or deleted by an
#: operator. Not the intake's to put back.
NOTE_REMOVED = "this ISBN was removed from the catalogue earlier — not added again"

#: Where a row remembers cover URLs `promote` found unusable. It lives in the
#: payload, beside what the source said, because that is the one thing a
#: re-crawl is compared against — and it is underscored because it is this
#: module's bookkeeping, not a field of the book (`Candidate.from_payload`
#: ignores it).
DEAD_COVERS_KEY = "_dead_cover_urls"
#: A book whose source cycles through bad images should not grow without bound.
_DEAD_COVERS_KEPT = 5

NOTE_NO_COVER_STORAGE = "waiting on cover storage: R2 is not configured"

#: What a book's own product page said, kept apart from what the feed says and
#: laid over it every time the row is staged. A storefront is crawled twice: a
#: feed that lists everything thinly, and a page per book that has the ISBN,
#: the author and — on mbibooks.com — the title in Malayalam where the feed has
#: only a romanization. The feed is re-read every night; without this, tonight's
#: thin row would overwrite last night's complete one.
PAGE_FACTS_KEY = "_page"
#: Set once a row's page has been read, whatever it yielded, so a page is
#: fetched once and not every night it stays incomplete.
PAGE_READ_KEY = "_page_read"
#: Marks a row first seen on a store's newest page — a new release, which is
#: published ahead of the backlog (owner, 3 Oct 2026: "new release should be
#: there in our db").
FRESH_KEY = "_fresh"
#: A reason this row must not be published until a person has looked at it.
#: Sticky, like the dead-cover list and for the same reason: the gate would
#: otherwise find the row complete again on the next pass and send it straight
#: back to `promote`.
HOLD_KEY = "_hold"
#: What `author_roles` was told about a row's credits: `asked` once it has
#: been asked (a paid call is not repeated nightly), `resolved` when the answer
#: stood up — the authors and translators to publish under — and `answer`, the
#: model's reply as given, for whoever reviews a row that did not resolve.
ROLES_KEY = "_roles"
#: Set on a row that was promoted as another printing of a Work that already
#: existed. Its `work_id` then names a book this pipeline did *not* create, and
#: `revert` has to know that: undoing the printing must not take the book.
PRINTING_KEY = "_printing"
#: Written to `missing` for a held row. Stable — the console reads it.
HELD_POSSIBLE_DUPLICATE = "possible_duplicate"


def _state_for(screened: intake_gate.Screened) -> str:
    if screened.rejected:
        return STATE_REJECTED
    return STATE_COMPLETE if screened.ok else STATE_INCOMPLETE


def _dead_covers(row: CatalogIntake) -> list[str]:
    return list((row.payload or {}).get(DEAD_COVERS_KEY) or ())


_EMPTY = (None, "", ())


def _blank_never_erases(existing: dict | None, incoming: Candidate) -> Candidate:
    """What the source says now, over what it said before.

    A field the source leaves out tonight is "not told", not "no longer true":
    a storefront drops a cover while it re-uploads it, a feed page comes back
    without the attribute it carried yesterday. The same rule the sync engine
    learned the hard way (CLAUDE.md, 15 Aug 2026) — an incoming null must not
    overwrite an answer.
    """
    if not existing or "source_key" not in existing:
        # Nothing staged yet — at most this module's own notes on a new row.
        return incoming
    before = Candidate.from_payload(existing)
    kept = {
        name: getattr(before, name)
        for name in Candidate.__dataclass_fields__
        if getattr(incoming, name) in _EMPTY and getattr(before, name) not in _EMPTY
    }
    return replace(incoming, **kept) if kept else incoming


def _with_page_facts(candidate: Candidate, facts: dict | None) -> Candidate:
    """Lay what the book's own page said over what the feed says."""
    if not facts:
        return candidate
    known = Candidate.__dataclass_fields__
    over = {
        name: tuple(value) if name in ("authors", "contributors", "translators") else value
        for name, value in facts.items()
        if name in known and value not in (None, "", [], ())
    }
    return replace(candidate, **over) if over else candidate


def _stage(row: CatalogIntake, candidate: Candidate) -> str:
    """Screen `candidate` and write the verdict onto `row`; returns the state.

    The one place a row's state, payload, gaps and note are set from the gate,
    so discovery, enrichment and re-screening cannot come to disagree about a
    rule. Three of them live here because every path has to honour them:

    - a blank in tonight's crawl never erases last night's answer;
    - what the book's own page said outranks what the feed says;
    - a cover URL `promote` already found unusable is withheld, whichever path
      offers it again — otherwise a source that keeps listing a dead image
      makes its book `complete`, and costs a fetch and a promotion slot, every
      night.
    """
    book = row.payload or {}
    # This module's own notes on the row (underscored) ride through untouched.
    kept = {key: value for key, value in book.items() if key.startswith("_")}

    dead = _dead_covers(row)
    if candidate.cover_url and candidate.cover_url.strip() in dead:
        candidate = replace(candidate, cover_url=None)
    candidate = _blank_never_erases(book, candidate)
    candidate = _with_page_facts(candidate, kept.get(PAGE_FACTS_KEY))
    # …and who-did-what, once resolved, outranks both: it is the one thing
    # neither the feed nor the page states.
    candidate = _with_page_facts(candidate, (kept.get(ROLES_KEY) or {}).get("resolved"))
    if candidate.cover_url and candidate.cover_url.strip() in dead:
        candidate = replace(candidate, cover_url=None)

    screened = intake_gate.screen(candidate)
    state = _state_for(screened)
    row.state = state
    row.isbn = screened.candidate.isbn
    payload = screened.candidate.to_payload()
    payload.update(kept)
    row.payload = payload
    row.missing = list(screened.fatal or screened.missing) or None
    note = _note_for(screened)
    if dead and intake_gate.MISSING_COVER in screened.missing:
        # Say which kind of "no cover" this is: the queue should not read as
        # though the source never had one.
        note = f"{note} (the cover this source offered is unusable)"
    if kept.get(ROLES_KEY) and intake_gate.MISSING_AUTHOR_ROLES in screened.missing:
        note = f"{note} (asked; the publisher's text does not say who did what)"
    if state == STATE_COMPLETE and kept.get(HOLD_KEY):
        # Nothing is missing from the record; what is missing is a decision.
        state = row.state = STATE_INCOMPLETE
        row.missing = [HELD_POSSIBLE_DUPLICATE]
        note = str(kept[HOLD_KEY])
    row.note = note
    return state


#: Rows looked up per query when staging. A storefront feed page is a hundred
#: candidates; one round trip for the page instead of one per book.
_LOOKUP_CHUNK = 200


async def record(
    db: AsyncSession,
    candidates: Iterable[Candidate],
    *,
    source: str,
    fresh: bool = False,
) -> dict[str, int]:
    """Screen candidates and stage them. Touches no catalogue table.

    Idempotent by `(source, source_key)`: a re-crawl updates the row it made
    last time rather than adding a second one. A row already promoted is left
    strictly alone — re-discovering a book we published is not a reason to
    reconsider it, and rewriting its payload would make the receipt describe
    something other than what was created.

    `fresh` says these came off a source's *newest* listing: a row created by
    such a pass is marked a new release and promoted ahead of the backlog. Only
    on creation — a book already staged does not become new by being seen
    again.
    """
    batch = list(candidates)
    existing: dict[str, CatalogIntake] = {}
    keys = list(dict.fromkeys(c.source_key for c in batch))
    for start in range(0, len(keys), _LOOKUP_CHUNK):
        rows = await db.execute(
            select(CatalogIntake).where(
                CatalogIntake.source == source,
                CatalogIntake.source_key.in_(keys[start : start + _LOOKUP_CHUNK]),
            )
        )
        existing.update({row.source_key: row for row in rows.scalars()})

    counts: dict[str, int] = {}
    for candidate in batch:
        row = existing.get(candidate.source_key)
        if row is None:
            row = CatalogIntake(source=source, source_key=candidate.source_key)
            if fresh:
                row.payload = {FRESH_KEY: True}
            db.add(row)
            # The same book twice in one batch updates the row just made.
            existing[candidate.source_key] = row
        elif row.state == STATE_PROMOTED:
            counts["already_promoted"] = counts.get("already_promoted", 0) + 1
            continue
        elif row.state == STATE_DUPLICATE:
            # Judged already: the catalogue has this book, or had it and it
            # was removed. The shops' newest pages are re-read every night, and
            # re-staging here would put the row back to `complete` to be
            # queued, fetched and judged again — every night, for ever.
            counts["already_settled"] = counts.get("already_settled", 0) + 1
            continue

        state = _stage(row, candidate)
        counts[state] = counts.get(state, 0) + 1

    await db.commit()
    return counts


def apply_roles(row: CatalogIntake, *, resolved: dict | None, answer: object) -> str:
    """Record what `author_roles` was told about this row and re-stage it.

    `resolved` is None when the answer did not stand up; the row is still
    marked asked, so the same question is not paid for again tomorrow.
    """
    roles: dict = {"asked": True, "answer": answer}
    if resolved:
        roles["resolved"] = resolved
    row.payload = {**(row.payload or {}), ROLES_KEY: roles}
    return _stage(row, Candidate.from_payload(row.payload))


def apply_page_facts(row: CatalogIntake, facts: dict) -> str:
    """Record what a row's own product page said and re-stage it.

    Called by `intake_storefront.enrich`. The page is marked read whatever it
    yielded: a page with nothing on it is still a page we need not fetch again.
    """
    row.payload = {**(row.payload or {}), PAGE_FACTS_KEY: facts, PAGE_READ_KEY: True}
    return _stage(row, Candidate.from_payload(row.payload))


def _note_for(screened: intake_gate.Screened) -> str | None:
    if screened.fatal:
        note = "refused: " + ", ".join(screened.fatal)
    elif screened.missing:
        note = "waiting on: " + ", ".join(screened.missing)
    else:
        note = None
    if screened.dropped:
        # The cleaning the gate did, where a person reading the queue can see it.
        said = "credit dropped: " + "; ".join(screened.dropped)
        note = f"{note} ({said})" if note else said
    return note


async def rescreen_incomplete(db: AsyncSession, *, limit: int = 500) -> dict[str, int]:
    """Re-run the gate over `incomplete` rows.

    Worth its own function because the gate is code and code changes: a rule
    relaxed or a bug fixed should release the rows it was holding, without
    re-crawling the source that found them. That is what storing the payload
    buys.
    """
    rows = (
        (
            await db.execute(
                select(CatalogIntake)
                .where(CatalogIntake.state == STATE_INCOMPLETE)
                .order_by(CatalogIntake.first_seen_at)
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    counts: dict[str, int] = {}
    for row in rows:
        state = _stage(row, Candidate.from_payload(row.payload))
        counts[state] = counts.get(state, 0) + 1
    await db.commit()
    return counts


def _work_create(candidate: Candidate) -> WorkCreate:
    """The same payload shape a reader's add-book form submits."""
    return WorkCreate(
        title=candidate.title,
        subtitle=candidate.subtitle,
        description=candidate.description,
        language=candidate.language,
        first_publish_year=candidate.first_publish_year,
        author_names=list(candidate.authors),
        translator_names=list(candidate.translators),
        publisher_name=candidate.publisher,
        isbn=candidate.isbn,
        page_count=candidate.page_count,
        format=candidate.format,
        cover_url=candidate.cover_url,
        back_cover_url=candidate.back_cover_url,
    )


def _edition_create(candidate: Candidate) -> EditionCreate:
    """The same candidate, as another printing of a Work that already exists."""
    return EditionCreate(
        publisher_name=candidate.publisher,
        isbn=candidate.isbn,
        language=candidate.language,
        page_count=candidate.page_count,
        format=candidate.format,
        cover_url=candidate.cover_url,
        back_cover_url=candidate.back_cover_url,
        # Work-level, and only ever fills a gap (see `create_edition`).
        description=candidate.description,
        first_publish_year=candidate.first_publish_year,
    )


_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)


def _strict(text: str | None) -> str:
    """Case, spacing and punctuation folded away; nothing else. Deliberately
    not `translit.fold`, which is a *search* skeleton and merges spellings."""
    return " ".join(_PUNCTUATION.sub(" ", (text or "").casefold()).split())


def _same_person(a: str, b: str) -> bool:
    """Two spellings of one name: equal once punctuation and case are folded,
    or one a shortened form of the other that keeps the surname — a shop's
    `Scott Fitzgerald` for `F. Scott Fitzgerald`. Deliberately not fuzzier
    than that: `K R Meera` and `Meera K R` are left for a person to pair."""
    x, y = _strict(a).split(), _strict(b).split()
    if not x or not y:
        return False
    if x == y:
        return True
    short, long = (x, y) if len(x) <= len(y) else (y, x)
    return len(short) >= 2 and short[-1] == long[-1] and set(short) <= set(long)


async def catalogue_spelling(db: AsyncSession, name: str) -> str:
    """The catalogue's own spelling of this person, when it already has them.

    A shop's spelling of a name is not the catalogue's. The first preview of a
    real night (4 Oct 2026) offered `Shakespeare William`, `Scott Fitzgerald`
    and `Chesterton G K`; published as written, each is a second author row
    for someone we already hold, and a second, thinner author page. So a name
    that is plainly an existing author's — the same words in another order, or
    a shortened form that keeps the surname — is replaced by the name on the
    row we have.

    Only when exactly one author matches. Two candidates is a question for a
    person, and the name goes through as the source wrote it.
    """
    words = _strict(name).split()
    if len(words) < 2:
        return name
    anchor = max(words, key=len)
    if len(anchor) < 3:
        return name
    known = (
        (
            await db.execute(
                select(Author.name)
                .where(Author.deleted_at.is_(None), Author.name.ilike(f"%{anchor}%"))
                .limit(200)
            )
        )
        .scalars()
        .all()
    )
    matches = {
        other
        for other in known
        if sorted(_strict(other).split()) == sorted(words) or _same_person(name, other)
    }
    if any(_strict(other) == _strict(name) for other in matches):
        return name  # already spelled the catalogue's way, give or take a full stop
    return matches.pop() if len(matches) == 1 else name


async def find_work(db: AsyncSession, candidate: Candidate) -> tuple[Work | None, bool]:
    """A Work already carrying this candidate's title, and whether it is the
    same book: `(work, True)` — another printing of it; `(work, False)` — the
    same title by someone else; `(None, False)` — nothing like it here.

    A storefront lists the hardback and the paperback as two products with two
    ISBNs, and each would otherwise become its own Work — two thin pages for
    one book, which is rule 17 broken at the door. So a printing is attached
    to the Work it belongs to. Matched narrowly on purpose: the same title,
    the same subtitle when both have one, the same language, and an author in
    common. A wrong attach puts one book's printing on another's page.

    The middle answer matters as much. `The Great Gatsby` by `Scott
    Fitzgerald` (a real row, harpercollins.co.in, 3 Oct 2026) may be the book
    we hold by a differently spelled author, or a different book that shares
    a title. An unattended job cannot tell, and both wrong guesses leave a
    record someone has to repair — so the caller holds it for a person.
    """
    key = fold(candidate.title)
    if not key or not candidate.authors:
        return None, False
    works = (
        (
            await db.execute(
                select(Work)
                .where(
                    Work.title_fold == key,
                    Work.deleted_at.is_(None),
                    Work.merged_into_id.is_(None),
                )
                .order_by(Work.created_at, Work.id)
                .limit(20)
            )
        )
        .scalars()
        .all()
    )
    title = _strict(candidate.title)
    namesake: Work | None = None
    for work in works:
        if _strict(work.title) != title:
            continue
        if work.subtitle and candidate.subtitle:
            if _strict(work.subtitle) != _strict(candidate.subtitle):
                continue
        if work.language and candidate.language:
            if work.language.casefold() != candidate.language.casefold():
                continue  # a translation is its own Work
        if any(
            _same_person(mine, theirs.name) for mine in candidate.authors for theirs in work.authors
        ):
            return work, True
        namesake = namesake or work
    return namesake, False


def _isbn_conflict_work_id(exc: HTTPException) -> uuid.UUID | None:
    """The work an `isbn_exists` 409 named, if it named one."""
    detail = exc.detail if isinstance(exc.detail, dict) else {}
    if detail.get("code") != "isbn_exists":
        return None
    raw = detail.get("work_id")
    try:
        return uuid.UUID(str(raw)) if raw else None
    except ValueError:
        return None


async def _work_by_provenance(
    db: AsyncSession, external_source: str, external_id: str
) -> uuid.UUID | None:
    """The live Work already created from this upstream record, if any."""
    return (
        await db.execute(
            select(Work.id).where(
                Work.external_source == external_source,
                Work.external_id == external_id,
                Work.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def already_catalogued(db: AsyncSession, candidate: Candidate) -> uuid.UUID | None:
    """The book this candidate already is, if the catalogue holds it.

    Two questions, because neither alone is enough:

    - **Same upstream record?** The `etl/` bulk load stamped 1,428 works with
      `openlibrary` + the OL work key. A second *printing* of one of them
      carries a different, unclaimed ISBN, so an ISBN check would pass it and
      we would publish a duplicate Work for a book already here.
    - **Same ISBN?** Two upstream records can name one printing — OpenLibrary
      itself carries duplicate work keys for popular books. Matched on
      `isbn.variants()`, so an ISBN-10 stored on an older printing is
      recognised when the candidate carries the 13.

    Read-only, which is what lets `scripts/preview_intake.py` ask exactly the
    question tonight's run will ask without writing anything. Promotion still
    keeps `create_work_with_edition`'s own guard behind this one: that catches
    the two cases a pre-check cannot — a soft-deleted row still occupying the
    number, and a reader adding the same printing in the same second.
    """
    by_provenance = await _work_by_provenance(db, *candidate.provenance)
    if by_provenance is not None:
        return by_provenance

    forms = isbn_util.variants(candidate.isbn) if candidate.isbn else None
    if not forms:
        return None
    return (
        await db.execute(
            select(Edition.work_id)
            .join(Work, Work.id == Edition.work_id)
            .where(
                Edition.isbn.in_(forms),
                Edition.deleted_at.is_(None),
                Work.deleted_at.is_(None),
            )
            .order_by(Edition.created_at, Edition.id)
            .limit(1)
        )
    ).scalar_one_or_none()


#: How many times the nightly limit of new releases to look at when sharing
#: the night between sources.
_FRESH_SOURCES_WINDOW = 4


def _taking_turns(rows: Sequence[Row], limit: int) -> list[Row]:
    """Up to `limit` rows, one source at a time. Anything with a `.source` will
    do; `_due` passes `(id, source)` rows.

    Every shop's newest page is staged within the same minute, so "newest
    first" alone means whichever shop was read last fills the whole night — on
    the first night, fifty books from one publisher and none in Malayalam.
    Sources take turns instead; within a source the order is kept.
    """
    queues: dict[str, list[Row]] = {}
    for row in rows:
        queues.setdefault(row.source, []).append(row)
    taken: list[Row] = []
    while queues and len(taken) < limit:
        for source in list(queues):
            taken.append(queues[source].pop(0))
            if not queues[source]:
                del queues[source]
            if len(taken) >= limit:
                break
    return taken


async def removed_earlier(db: AsyncSession, candidate: Candidate) -> uuid.UUID | None:
    """The book this candidate's ISBN *used* to be, if it was taken out.

    `editions_isbn_key` is a plain unique index, so a soft-deleted edition
    still occupies its number: creating the book again can only fail. And it
    should not be tried — a book that was undone with `revert`, or deleted in
    the console, was removed by a person, and a nightly job that quietly puts
    it back is the opposite of what they asked for.

    Asked after `already_catalogued` (a live book wins) and before anything is
    fetched. Read-only, so `scripts/preview_intake.py` asks it too.
    """
    forms = isbn_util.variants(candidate.isbn) if candidate.isbn else None
    if not forms:
        return None
    return (
        await db.execute(
            select(Edition.work_id)
            .join(Work, Work.id == Edition.work_id)
            .where(
                Edition.isbn.in_(forms),
                or_(Edition.deleted_at.is_not(None), Work.deleted_at.is_not(None)),
            )
            .limit(1)
        )
    ).scalar_one_or_none()


async def _due(db: AsyncSession, limit: int) -> list[Row]:
    """Tonight's candidates, as `(id, source)`: new releases first, then the
    backlist — and in both, one source at a time.

    Without the first half a book published this week waits behind every
    backlist title staged before it — months, at the daily limit. The newest
    of the new go first, so a busy week never pushes this week's books out by
    last week's.

    The backlist takes turns too (5 Oct 2026). It used to be taken strictly in
    the order it was found, and OpenLibrary is crawled first every night — so
    Mathrubhumi's 237 ready books sat behind 181 of OpenLibrary's and two
    nights went out entirely in English. Within a source the order found is
    kept; when the others run dry, the one that has books fills the night.

    Ids and sources only. The rows carry every candidate's whole payload
    (blurb, biographies, the LLM's reply), choosing a night used to load up to
    600 of them to keep 150, and this database's bytes out are metered —
    `promote` loads each row when its turn comes.
    """
    ready = (CatalogIntake.state == STATE_COMPLETE, CatalogIntake.attempts < MAX_ATTEMPTS)
    is_fresh = CatalogIntake.payload.has_key(FRESH_KEY)  # noqa: W601 — JSONB `?`, not dict
    newest = (
        await db.execute(
            select(CatalogIntake.id, CatalogIntake.source)
            .where(*ready, is_fresh)
            .order_by(CatalogIntake.first_seen_at.desc(), CatalogIntake.id)
            # Wider than the limit, so there is something to take turns over.
            .limit(limit * _FRESH_SOURCES_WINDOW)
        )
    ).all()
    fresh = _taking_turns(newest, limit)
    if len(fresh) >= limit:
        return fresh

    room = limit - len(fresh)
    # Each source's own oldest `room` — enough for any one of them to fill the
    # night alone — ranked in the database so no source's long queue has to be
    # read past to reach another's.
    turn = (
        func.row_number()
        .over(
            partition_by=CatalogIntake.source,
            order_by=(CatalogIntake.first_seen_at, CatalogIntake.id),
        )
        .label("turn")
    )
    queued = (
        select(CatalogIntake.id, CatalogIntake.source, CatalogIntake.first_seen_at, turn)
        .where(*ready, ~is_fresh)
        .subquery()
    )
    backlist = (
        await db.execute(
            select(queued.c.id, queued.c.source)
            .where(queued.c.turn <= room)
            .order_by(queued.c.first_seen_at, queued.c.id)
        )
    ).all()
    return [*fresh, *_taking_turns(backlist, room)]


async def _own_covers(
    candidate: Candidate, covers: cover_ingest.Ingester | None
) -> tuple[Candidate | None, cover_ingest.Ingested | None]:
    """The candidate carrying covers we may publish, or why there is none.

    - `(candidate, None)` — ready; its cover URLs are ones every client serves.
    - `(None, verdict)` — the front cover could not be ingested, and
      `verdict.gone` says whether asking again could help.
    - `(None, None)` — the cover sits on a host nothing has been told about
      and there is no storage configured to bring it home, so the book waits.

    The back cover is a bonus and is never a reason to hold a book: if it
    cannot be ingested the book is published without one, which is how most
    books in the catalogue already are.
    """
    settings = get_settings()
    front, back = candidate.cover_url, candidate.back_cover_url

    if covers is None:
        if not cover_ingest.servable_as_is(settings, front):
            return None, None
        if back and not cover_ingest.servable_as_is(settings, back):
            back = None
        return replace(candidate, back_cover_url=back), None

    if not cover_ingest.is_ours(settings, front):
        verdict = await covers(front)
        if verdict.url is None:
            return None, verdict
        front = verdict.url
    if back and not cover_ingest.is_ours(settings, back):
        back = (await covers(back)).url
    return replace(candidate, cover_url=front, back_cover_url=back), None


async def promote(
    db: AsyncSession, *, limit: int, covers: cover_ingest.Ingester | None = None
) -> dict[str, int]:
    """Turn up to `limit` complete candidates into catalogue books.

    One book per transaction (`create_work_with_edition` commits), so a failure
    on the fourth leaves the first three published — never a half-written
    book. Every outcome is written back onto the candidate before moving on, so
    an interrupted run (a Railway redeploy mid-batch, say) resumes rather than
    repeating: the rows it finished are no longer `complete`.

    **One row cannot end the run.** On 5 Oct 2026 it did: the second row of the
    night was a book that had been undone, its ISBN conflict rolled the session
    back, and a rollback *expires every object the session holds* — so the
    third row's first attribute read was a lazy load with nowhere to run
    (`MissingGreenlet`), and the job died having published one book with 1,070
    ready. Hence the two things below that look like ceremony: the batch is
    carried as ids and each row is loaded when its turn comes, and every row
    runs inside a guard that counts an unplanned failure and moves on.

    `covers` is `cover_ingest.ingester(...)` — None when R2 is not configured,
    in which case only a cover the edge proxy already serves is published
    as-is and everything else waits (see `_own_covers`).
    """
    counts: dict[str, int] = {}
    run = _Run()
    for row_id in [due.id for due in await _due(db, limit)]:
        try:
            row = await db.get(CatalogIntake, row_id)
            if row is None or row.state != STATE_COMPLETE:
                continue
            stop = await _promote_one(db, row, covers, counts, run)
        except Exception as exc:  # noqa: BLE001 — one row must not end the night
            logger.exception("intake: promoting %s failed in a way nobody planned for", row_id)
            await _charge_unplanned(db, row_id, exc)
            counts["error"] = counts.get("error", 0) + 1
            run.errors += 1
            if run.errors >= MAX_CONSECUTIVE_ERRORS:
                logger.error(
                    "intake: %s unplanned failures in a row — stopping this run", run.errors
                )
                break
            continue
        run.errors = 0
        if stop:
            break

    return counts


class _Run:
    """What a promotion run carries from one row to the next."""

    __slots__ = ("cover_failures", "errors")

    def __init__(self) -> None:
        self.cover_failures = 0
        self.errors = 0


async def _charge_unplanned(db: AsyncSession, row_id: uuid.UUID, exc: Exception) -> None:
    """Record an unplanned failure on its row, from a clean session.

    The attempt is what keeps a row that fails every night from being first in
    line every night: `_due` skips a row at `MAX_ATTEMPTS`. Best-effort — if
    even this cannot be written, the run still goes on to the next row.
    """
    try:
        await db.rollback()
        row = await db.get(CatalogIntake, row_id)
        if row is not None and row.state == STATE_COMPLETE:
            row.attempts += 1
            row.note = f"promote crashed: {type(exc).__name__}"
            await db.commit()
    except Exception:  # noqa: BLE001 — recording the failure must not become one
        logger.exception("intake: could not record the failure on %s", row_id)
        try:
            await db.rollback()
        except Exception:  # noqa: BLE001
            pass


async def _promote_one(
    db: AsyncSession,
    row: CatalogIntake,
    covers: cover_ingest.Ingester | None,
    counts: dict[str, int],
    run: _Run,
) -> bool:
    """Take one due candidate as far as it goes. True means "stop the run"."""
    candidate = Candidate.from_payload(row.payload)

    # The gate again, on the row we are about to publish. It has already
    # passed once, but that was possibly weeks and certainly one deploy
    # ago, and this is the last moment before a public page exists.
    screened = intake_gate.screen(candidate)
    if not screened.ok:
        row.state = _state_for(screened)
        row.missing = list(screened.fatal or screened.missing) or None
        row.note = _note_for(screened)
        await db.commit()
        counts["regressed"] = counts.get("regressed", 0) + 1
        return False

    # The same question `scripts/preview_intake.py` asks, so a preview and
    # the run it previews cannot disagree.
    existing_id = await already_catalogued(db, screened.candidate)
    if existing_id is not None:
        row.state = STATE_DUPLICATE
        row.work_id = existing_id
        row.note = "already in the catalogue"
        await db.commit()
        counts[STATE_DUPLICATE] = counts.get(STATE_DUPLICATE, 0) + 1
        return False

    removed_id = await removed_earlier(db, screened.candidate)
    if removed_id is not None:
        row.state = STATE_DUPLICATE
        row.work_id = removed_id
        row.note = NOTE_REMOVED
        await db.commit()
        counts["removed_earlier"] = counts.get("removed_earlier", 0) + 1
        return False

    # Credit the author the catalogue already has, under the name it has
    # them by, rather than adding a second row for a shop's spelling.
    named = replace(
        screened.candidate,
        authors=tuple(
            dict.fromkeys(
                [await catalogue_spelling(db, name) for name in screened.candidate.authors]
            )
        ),
    )
    screened = replace(screened, candidate=named)

    # Another printing of a book we hold is added to that book; the same
    # title by a different author is not ours to call either way. Asked
    # before the cover is fetched, so a held row costs nothing.
    parent, same_book = await find_work(db, screened.candidate)
    if parent is not None and not same_book:
        row.payload = {
            **row.payload,
            HOLD_KEY: f"held: same title as a book already in the catalogue ({parent.id})"
            " by a different author",
        }
        _stage(row, screened.candidate)
        await db.commit()
        counts["held_duplicate"] = counts.get("held_duplicate", 0) + 1
        return False

    # After the duplicate check, so a book we already hold never costs a
    # fetch or leaves an object in the bucket; before creation, so no book
    # is ever live pointing at a cover that turned out not to load.
    publishable, failure = await _own_covers(screened.candidate, covers)
    if publishable is None:
        if failure is None:
            row.note = NOTE_NO_COVER_STORAGE
            counts["held"] = counts.get("held", 0) + 1
        elif failure.gone:
            dead = [*_dead_covers(row), screened.candidate.cover_url][-_DEAD_COVERS_KEPT:]
            row.payload = {**row.payload, "cover_url": None, DEAD_COVERS_KEY: dead}
            row.state = STATE_INCOMPLETE
            row.missing = [intake_gate.MISSING_COVER]
            row.note = f"cover unusable: {failure.reason}"
            counts["cover_unusable"] = counts.get("cover_unusable", 0) + 1
            run.cover_failures = 0
            logger.info(
                "intake: unusable cover for %s (%s): %s",
                row.source_key,
                failure.reason,
                screened.candidate.cover_url,
            )
        else:
            row.attempts += 1
            row.note = f"cover not fetched: {failure.reason}"
            counts["cover_retry"] = counts.get("cover_retry", 0) + 1
            run.cover_failures += 1
        await db.commit()
        if run.cover_failures >= MAX_CONSECUTIVE_COVER_FAILURES:
            logger.info(
                "intake: %s consecutive cover failures — stopping this run", run.cover_failures
            )
            return True
        return False
    run.cover_failures = 0

    try:
        if parent is not None:
            edition = await catalog_service.create_edition(db, parent, _edition_create(publishable))
            row.state = STATE_PROMOTED
            row.work_id = parent.id
            row.edition_id = edition.id
            row.promoted_at = datetime.now(UTC)
            row.payload = {**row.payload, PRINTING_KEY: True}
            row.note = "added as a printing of a book already in the catalogue"
            await db.commit()
            counts["printing"] = counts.get("printing", 0) + 1
            return False
        work = await catalog_service.create_work_with_edition(
            db, _work_create(publishable), created_by=None
        )
    except HTTPException as exc:
        # The ISBN guard rolls the session back before it raises, and a
        # rollback expires this row with everything else. Load it again here,
        # where there is somewhere for the query to run, before reading it.
        await db.refresh(row)
        duplicate_of = _isbn_conflict_work_id(exc)
        if duplicate_of is None and exc.status_code != 409:
            # Something other than "already catalogued" — count the attempt
            # and let it come round again.
            row.attempts += 1
            row.note = f"promote failed: {exc.status_code}"
            await db.commit()
            counts["failed"] = counts.get("failed", 0) + 1
            logger.warning("intake: promote failed for %s: %s", row.source_key, exc.detail)
            return False
        row.state = STATE_DUPLICATE
        row.work_id = duplicate_of
        row.note = "already in the catalogue with this ISBN"
        await db.commit()
        counts[STATE_DUPLICATE] = counts.get(STATE_DUPLICATE, 0) + 1
        return False

    row.state = STATE_PROMOTED
    row.work_id = work.id
    # Index 0 is safe here in a way it is not elsewhere (13 Aug 2026): we
    # created this Work a line ago and it has exactly one printing.
    row.edition_id = work.editions[0].id if work.editions else None
    row.promoted_at = datetime.now(UTC)
    row.note = None
    # The receipt commits on its own, BEFORE provenance. They were one
    # commit at first, which quietly made the less important write able to
    # lose the more important one: a rollback would have left a published
    # book whose candidate still read `complete`, due for promotion again.
    await db.commit()
    # Provenance is set after the fact because `WorkCreate` deliberately
    # does not carry it: `POST /catalog/works` is reader-facing, and a
    # field that says "this came from OpenLibrary" must not be settable by
    # whoever is posting. Best-effort — losing it costs this book's
    # recognition on a future run, which the ISBN guard still catches, and
    # that is not worth widening a public schema for.
    await _stamp_provenance(db, work, screened.candidate)
    counts[STATE_PROMOTED] = counts.get(STATE_PROMOTED, 0) + 1
    return False


async def _stamp_provenance(db: AsyncSession, work: Work, candidate: Candidate) -> None:
    work.external_source, work.external_id = candidate.provenance
    try:
        await db.commit()
    except Exception:  # noqa: BLE001 — provenance is not worth losing the book
        await db.rollback()
        logger.warning("intake: could not stamp provenance on %s", work.id)


#: How far apart an author row and the Work it was created for can be. They
#: are written in one transaction, so in practice this is zero.
_SAME_PROMOTION = timedelta(seconds=2)


async def _credits(db: AsyncSession, person: Author, *, live: bool) -> list[datetime]:
    """When each book crediting `person` was created — the live ones, or the
    soft-deleted ones."""
    stamps: list[datetime] = []
    for link in (work_authors, work_translators):
        gone = Work.deleted_at.is_(None) if live else Work.deleted_at.is_not(None)
        rows = await db.execute(
            select(Work.created_at)
            .join(link, link.c.work_id == Work.id)
            .where(link.c.author_id == person.id, gone)
        )
        stamps.extend(rows.scalars())
    return stamps


async def retire_orphaned_authors(db: AsyncSession, works: Iterable[Work]) -> int:
    """Soft-delete the author rows that undone books leave with nothing.

    Undoing `Classic Dark Stories` by `Various` should not leave an author
    page called "Various" behind with no books on it. A row is retired only if
    both things are true:

    - **no live book names them** any more; and
    - **the row was made for a book that has since been undone** — it was
      created in the same breath as one of them. An author the catalogue
      already had before these books is left exactly as it was.

    Asked of the person's whole history rather than of the one book in hand,
    because one author row can be made for the first of two books and shared
    by the second: undoing both, in either order or on different days, has to
    end with the row gone (`BOOKTOPUS`, 4 Oct 2026 — the first version of
    this looked at each book alone and left it standing).
    """
    people = {person.id: person for work in works for person in (*work.authors, *work.translators)}
    retired = 0
    for person in people.values():
        if person.deleted_at is not None or await _credits(db, person, live=True):
            continue
        undone = await _credits(db, person, live=False)
        if any(abs(person.created_at - made) <= _SAME_PROMOTION for made in undone):
            person.deleted_at = datetime.now(UTC)
            retired += 1
    return retired


async def revert(db: AsyncSession, intake_ids: Iterable[uuid.UUID]) -> int:
    """Undo promotions this pipeline made — the receipt, read backwards.

    Soft delete only (rule 3), and only what this pipeline created. For a row
    that published a book, that is the Work and its editions: the intake row's
    `work_id` is the proof of authorship. For a row that was added as another
    printing of a book already here, it is **that one Edition and nothing
    else** — its `work_id` names a book somebody else created, with readers'
    shelves and reviews on it, and undoing the printing must leave it standing.

    A reader may already have shelved what is being undone, which is exactly
    why it is soft-deleted rather than removed — their library entry keeps
    pointing at something.
    """
    reverted = 0
    undone: list[Work] = []
    for intake_id in intake_ids:
        row = await db.get(CatalogIntake, intake_id)
        if row is None or row.state != STATE_PROMOTED or row.work_id is None:
            continue
        now = datetime.now(UTC)
        if (row.payload or {}).get(PRINTING_KEY):
            edition = await db.get(Edition, row.edition_id) if row.edition_id else None
            if edition is not None and edition.deleted_at is None:
                edition.deleted_at = now
            # No longer a printing of anything; if it is promoted again it is
            # judged afresh.
            row.payload = {k: v for k, v in row.payload.items() if k != PRINTING_KEY}
        else:
            work = await db.get(Work, row.work_id)
            if work is not None and work.deleted_at is None:
                work.deleted_at = now
                for edition in work.editions:
                    edition.deleted_at = now
                undone.append(work)
        row.state = STATE_COMPLETE
        row.note = "reverted"
        row.promoted_at = None
        reverted += 1
    # Once every book in the batch is gone, so an author two of them shared is
    # judged against all of them.
    await db.flush()
    await retire_orphaned_authors(db, undone)
    await db.commit()
    return reverted
