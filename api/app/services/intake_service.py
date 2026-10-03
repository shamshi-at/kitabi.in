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
import uuid
from collections.abc import Iterable, Sequence
from dataclasses import replace
from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import CatalogIntake
from app.models.catalog_intake import (
    STATE_COMPLETE,
    STATE_DUPLICATE,
    STATE_INCOMPLETE,
    STATE_PROMOTED,
    STATE_REJECTED,
)
from app.models.edition import Edition
from app.models.work import Work
from app.schemas.catalog import WorkCreate
from app.services import catalog_service, cover_ingest, intake_gate
from app.services import isbn as isbn_util
from app.services.intake_gate import Candidate

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

#: Where a row remembers cover URLs `promote` found unusable. It lives in the
#: payload, beside what the source said, because that is the one thing a
#: re-crawl is compared against — and it is underscored because it is this
#: module's bookkeeping, not a field of the book (`Candidate.from_payload`
#: ignores it).
DEAD_COVERS_KEY = "_dead_cover_urls"
#: A book whose source cycles through bad images should not grow without bound.
_DEAD_COVERS_KEPT = 5

NOTE_NO_COVER_STORAGE = "waiting on cover storage: R2 is not configured"


def _state_for(screened: intake_gate.Screened) -> str:
    if screened.rejected:
        return STATE_REJECTED
    return STATE_COMPLETE if screened.ok else STATE_INCOMPLETE


def _dead_covers(row: CatalogIntake) -> list[str]:
    return list((row.payload or {}).get(DEAD_COVERS_KEY) or ())


def _stage(row: CatalogIntake, candidate: Candidate) -> str:
    """Screen `candidate` and write the verdict onto `row`; returns the state.

    The one place a row's state, payload, gaps and note are set from the gate,
    so discovery and re-screening cannot come to disagree about a rule — and
    the rule that needs that most is this one: a cover URL `promote` already
    found unusable is withheld from the gate, whichever path offers it again.
    Without that, a source that keeps listing a dead image would make its book
    `complete` every night and cost a fetch and a promotion slot every night.
    """
    dead = _dead_covers(row)
    if candidate.cover_url and candidate.cover_url.strip() in dead:
        candidate = replace(candidate, cover_url=None)

    screened = intake_gate.screen(candidate)
    state = _state_for(screened)
    row.state = state
    row.isbn = screened.candidate.isbn
    payload = screened.candidate.to_payload()
    if dead:
        payload[DEAD_COVERS_KEY] = dead
    row.payload = payload
    row.missing = list(screened.fatal or screened.missing) or None
    note = _note_for(screened)
    if dead and intake_gate.MISSING_COVER in screened.missing:
        # Say which kind of "no cover" this is: the queue should not read as
        # though the source never had one.
        note = f"{note} (the cover this source offered is unusable)"
    row.note = note
    return state


async def record(
    db: AsyncSession, candidates: Iterable[Candidate], *, source: str
) -> dict[str, int]:
    """Screen candidates and stage them. Touches no catalogue table.

    Idempotent by `(source, source_key)`: a re-crawl updates the row it made
    last time rather than adding a second one. A row already promoted is left
    strictly alone — re-discovering a book we published is not a reason to
    reconsider it, and rewriting its payload would make the receipt describe
    something other than what was created.
    """
    counts: dict[str, int] = {}
    for candidate in candidates:
        row = (
            await db.execute(
                select(CatalogIntake).where(
                    CatalogIntake.source == source,
                    CatalogIntake.source_key == candidate.source_key,
                )
            )
        ).scalar_one_or_none()

        if row is None:
            row = CatalogIntake(source=source, source_key=candidate.source_key)
            db.add(row)
        elif row.state == STATE_PROMOTED:
            counts["already_promoted"] = counts.get("already_promoted", 0) + 1
            continue

        state = _stage(row, candidate)
        counts[state] = counts.get(state, 0) + 1

    await db.commit()
    return counts


def _note_for(screened: intake_gate.Screened) -> str | None:
    if screened.fatal:
        return "refused: " + ", ".join(screened.fatal)
    if screened.missing:
        return "waiting on: " + ", ".join(screened.missing)
    return None


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
        publisher_name=candidate.publisher,
        isbn=candidate.isbn,
        page_count=candidate.page_count,
        cover_url=candidate.cover_url,
        back_cover_url=candidate.back_cover_url,
    )


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


async def _due(db: AsyncSession, limit: int) -> Sequence[CatalogIntake]:
    return (
        (
            await db.execute(
                select(CatalogIntake)
                .where(
                    CatalogIntake.state == STATE_COMPLETE,
                    CatalogIntake.attempts < MAX_ATTEMPTS,
                )
                .order_by(CatalogIntake.first_seen_at, CatalogIntake.id)
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )


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
    on the fourth leaves the first three published and the rest untouched —
    never a half-written book. Every outcome is written back onto the candidate
    before moving on, so an interrupted run (a Railway redeploy mid-batch, say)
    resumes rather than repeating: the rows it finished are no longer
    `complete`.

    `covers` is `cover_ingest.ingester(...)` — None when R2 is not configured,
    in which case only a cover the edge proxy already serves is published
    as-is and everything else waits (see `_own_covers`).
    """
    counts: dict[str, int] = {}
    cover_failures = 0
    for row in await _due(db, limit):
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
            continue

        # The same question `scripts/preview_intake.py` asks, so a preview and
        # the run it previews cannot disagree.
        existing_id = await already_catalogued(db, screened.candidate)
        if existing_id is not None:
            row.state = STATE_DUPLICATE
            row.work_id = existing_id
            row.note = "already in the catalogue"
            await db.commit()
            counts[STATE_DUPLICATE] = counts.get(STATE_DUPLICATE, 0) + 1
            continue

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
                cover_failures = 0
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
                cover_failures += 1
            await db.commit()
            if cover_failures >= MAX_CONSECUTIVE_COVER_FAILURES:
                logger.info(
                    "intake: %s consecutive cover failures — stopping this run", cover_failures
                )
                break
            continue
        cover_failures = 0

        try:
            work = await catalog_service.create_work_with_edition(
                db, _work_create(publishable), created_by=None
            )
        except HTTPException as exc:
            duplicate_of = _isbn_conflict_work_id(exc)
            if duplicate_of is None and exc.status_code != 409:
                # Something other than "already catalogued" — count the attempt
                # and let it come round again.
                row.attempts += 1
                row.note = f"promote failed: {exc.status_code}"
                await db.commit()
                counts["failed"] = counts.get("failed", 0) + 1
                logger.warning("intake: promote failed for %s: %s", row.source_key, exc.detail)
                continue
            row.state = STATE_DUPLICATE
            row.work_id = duplicate_of
            row.note = "already in the catalogue with this ISBN"
            await db.commit()
            counts[STATE_DUPLICATE] = counts.get(STATE_DUPLICATE, 0) + 1
            continue

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

    return counts


async def _stamp_provenance(db: AsyncSession, work: Work, candidate: Candidate) -> None:
    work.external_source, work.external_id = candidate.provenance
    try:
        await db.commit()
    except Exception:  # noqa: BLE001 — provenance is not worth losing the book
        await db.rollback()
        logger.warning("intake: could not stamp provenance on %s", work.id)


async def revert(db: AsyncSession, intake_ids: Iterable[uuid.UUID]) -> int:
    """Undo promotions this pipeline made — the receipt, read backwards.

    Soft delete only (rule 3), and only rows this pipeline created: the intake
    row's `work_id` is the proof of authorship. A reader may already have
    shelved the book, which is exactly why the Work is soft-deleted rather than
    removed — their library entry keeps pointing at something.
    """
    reverted = 0
    for intake_id in intake_ids:
        row = await db.get(CatalogIntake, intake_id)
        if row is None or row.state != STATE_PROMOTED or row.work_id is None:
            continue
        work = await db.get(Work, row.work_id)
        if work is not None and work.deleted_at is None:
            work.deleted_at = datetime.now(UTC)
            for edition in work.editions:
                edition.deleted_at = work.deleted_at
        row.state = STATE_COMPLETE
        row.note = "reverted"
        row.promoted_at = None
        reverted += 1
    await db.commit()
    return reverted
