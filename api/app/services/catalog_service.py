"""Shared catalog (Layer 1) business logic — server-authoritative works, editions,
authors, publishers, genres, series. Case-insensitive get-or-create dedupe, ISBN
lookup with OpenLibrary cache-on-first-use, and tuned eager-loading for detail vs.
list reads. Catalog rows carry no client-generated id; user contributions land here
via the API when online (CLAUDE.md rule 2)."""

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import and_, func, literal, or_, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload

from app.models import (
    CLAIM_APPROVED,
    CLAIM_PENDING,
    CLAIM_REJECTED,
    Author,
    AuthorClaim,
    Edition,
    Genre,
    LibraryEntry,
    Profile,
    Publisher,
    Rating,
    Review,
    Series,
    Work,
    WorkRevision,
    work_authors,
    work_genres,
    work_translators,
)
from app.schemas.catalog import (
    WORK_FORMS,
    EditionCreate,
    EditionUpdate,
    WorkCreate,
    WorkUpdate,
)
from app.services import isbn as isbn_util
from app.services import slug_service
from app.services.openlibrary_client import OpenLibraryClient, normalize_isbn_lookup
from app.services.translit import fold, transliterate

# Explicit eager loading everywhere a Work is fetched for serialization.
# Relying on the models' default `lazy=` strategy is NOT enough on its own in
# async SQLAlchemy — whether it actually eager-loads depends on the access
# path (get() vs select() vs refresh()), and a plain attribute access that
# falls through to a lazy load outside an awaited call raises MissingGreenlet.
# For fetching ONE work (book detail, add/edit, ISBN lookup): a single joined
# query instead of selectinload's four round-trips. On a high-latency DB link
# that's ~4x faster; the cartesian product is trivial for one work, and
# result.unique() dedupes it. Use _WORK_OPTIONS for LISTS, where a cross-join
# would multiply rows.
_WORK_JOINED = (
    joinedload(Work.authors),
    joinedload(Work.translators),
    joinedload(Work.genres),
    joinedload(Work.editions).options(joinedload(Edition.publisher), joinedload(Edition.series)),
)

# For summary LISTS (browse/search) — WorkSummaryOut needs authors, translators
# (the "trans. X" line on sibling rows) and a representative edition, but not
# genres, so skip that relationship to save a round-trip per list query.
_SUMMARY_OPTIONS = (
    selectinload(Work.authors),
    selectinload(Work.translators),
    selectinload(Work.editions).options(joinedload(Edition.publisher), joinedload(Edition.series)),
)


def cover_edition(work):  # noqa: ANN001, ANN201 — Work ORM in, Edition|None out
    """The printing a Work is represented by: the oldest edition that actually
    has a cover, falling back to the oldest of any.

    Deterministic on purpose — "whatever the DB returned first" would let the
    same book show a different cover on two identical requests, and on the web
    that image is the book page's LCP element. Lives here, not in a caller,
    because several surfaces need the same answer and the app additionally
    needs the *edition* itself: reviews attach to the Work (rule 17), but the
    app's book route is keyed on work + edition, so something has to choose."""
    editions = sorted(work.editions, key=lambda e: (e.created_at, e.id))
    for edition in editions:
        if edition.cover_url:
            return edition
    return editions[0] if editions else None


def work_cover(work) -> str | None:  # noqa: ANN001 — Work ORM instance
    edition = cover_edition(work)
    return edition.cover_url if edition else None


def looks_like_isbn(query: str) -> bool:
    """Kept as the catalog service's own name for a rule that now lives in
    `services/isbn` alongside the checksum arithmetic that has to agree with it."""
    return isbn_util.looks_like_isbn(query)


def _fuzzy_match(col, q: str):  # noqa: ANN001 — SQLAlchemy column expression
    """Typo-tolerant match predicate for one text column — plain containment
    plus pg_trgm similarity (`%`) and word-similarity (`<%`), every branch
    served by the GIN gin_trgm_ops indexes (migrations 000018/000019). Below
    3 characters trigrams are pure noise, so short queries stay containment-only.
    """
    like = col.ilike(f"%{q}%")
    if len(q) < 3:
        return like
    return or_(like, col.op("%")(q), literal(q).op("<%")(col))


def _rank(col, q: str):  # noqa: ANN001 — SQLAlchemy column expression
    """Relevance score for ordering: the best of whole-string similarity and
    best-matching-word-span similarity, so an exact-ish hit beats a loose one
    and a short query ranks well against a long title."""
    return func.greatest(func.similarity(col, q), func.word_similarity(q, col))


async def _relax_word_similarity(db: AsyncSession) -> None:
    """Drop pg_trgm's `<%` threshold from its 0.6 default for this transaction
    (SET LOCAL — transaction-scoped, so safe through the Supavisor pooler).

    Cross-romanization pairs land just under the default: the user's
    conventional "thakazhi" scores 0.56 against ITRANS's "takazhi …", so the
    word-similarity operator would drop exactly the matches the cross-script
    search exists for. Ranking still puts the closest hit first."""
    await db.execute(text("SET LOCAL pg_trgm.word_similarity_threshold = 0.45"))


async def _get_or_create(db: AsyncSession, model: type, name: str) -> object:
    """Case-insensitive get-or-create by name — authors/publishers/genres/series
    all share this shape. Catalog entities are server-authoritative (no
    client-generated id), so a plain insert-if-missing is correct here."""
    stmt = select(model).where(model.name.ilike(name.strip()))
    existing = (await db.execute(stmt)).scalar_one_or_none()
    if existing is not None:
        return existing
    row = model(name=name.strip())
    db.add(row)
    await db.flush()
    # Authors/publishers/series reached this way (free-text on the add form,
    # OpenLibrary caching, CSV import) need a public URL just as much as ones
    # created through create_author/create_publisher — this is the path those
    # flows actually take. Genre has no slug column and is skipped.
    if hasattr(model, "slug"):
        await slug_service.ensure_slug(db, row)
    return row


async def create_author(db: AsyncSession, **fields: object) -> Author:
    """Author picker's "add new" flow — get-or-create by name, populating the
    extra detail fields (pen_name/image_url/primary_language/bio) only when we
    actually insert a new row. Idempotent on name, so a race just returns the
    existing canonical author rather than a duplicate.

    `is_me=True` (the "This is me" checkbox) no longer links the row: it files
    a pending [AuthorClaim] for `created_by_user_id`, on both the insert and
    the get-or-create-hit path. See app/models/author_claim.py for why."""
    is_me = bool(fields.pop("is_me", False))
    created_by = fields.get("created_by_user_id")
    name = str(fields["name"]).strip()
    existing = (
        await db.execute(select(Author).where(Author.name.ilike(name)))
    ).scalar_one_or_none()
    if existing is not None:
        # Get-or-create hit: "This is me" on a name that already exists is the
        # same unverifiable claim as tapping it on the author's page, so it
        # queues too — otherwise typing an existing author's name into the add
        # form would be a way around review.
        if is_me and created_by is not None and existing.linked_user_id is None:
            await record_claim(db, existing, created_by)
        return existing
    author = Author(**{**fields, "name": name})
    db.add(author)
    await db.flush()
    await slug_service.ensure_slug(db, author)
    await db.commit()
    await db.refresh(author)
    # Even on a brand-new row the link is queued, never applied (owner
    # decision, 22 Jul 2026): applying it here would leave creating a duplicate
    # Author for a famous name as an instant, unreviewed way to become them.
    if is_me and created_by is not None:
        await record_claim(db, author, created_by)
    return author


async def claim_author(db: AsyncSession, author_id: uuid.UUID, user_id: uuid.UUID) -> AuthorClaim:
    """ "This is me" on an existing Author row — queues a claim for manual
    review instead of linking on the spot (owner decision, 22 Jul 2026).

    Nothing about the shared row changes here: `authors.linked_user_id` is
    written only by [approve_claim], so every other reader keeps seeing the old
    value while this sits pending. Idempotent — re-claiming returns the
    existing row rather than stacking duplicates.
    """
    author = await db.get(Author, author_id)
    if author is None or author.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Author not found"},
        )
    if author.linked_user_id == user_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "already_yours", "message": "This author is already linked to you"},
        )
    if author.linked_user_id is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "already_linked",
                "message": "This author is already linked to another reader",
            },
        )
    return await record_claim(db, author, user_id)


async def record_claim(db: AsyncSession, author: Author, user_id: uuid.UUID) -> AuthorClaim:
    """Get-or-create this reader's claim on `author`.

    A rejected claim is *not* silently reopened — a decision that has been made
    should not be undone by tapping the button again; that needs a human.
    """
    existing = (
        await db.execute(
            select(AuthorClaim).where(
                AuthorClaim.author_id == author.id, AuthorClaim.user_id == user_id
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    claim = AuthorClaim(author_id=author.id, user_id=user_id)
    db.add(claim)
    await db.commit()
    await db.refresh(claim)
    return claim


async def pending_claim_author_ids(
    db: AsyncSession, user_id: uuid.UUID, author_ids: Sequence[uuid.UUID]
) -> set[uuid.UUID]:
    """Which of `author_ids` this reader has an unresolved claim on — the only
    thing that makes a pending claim visible, and only to its claimant."""
    if not author_ids:
        return set()
    rows = await db.execute(
        select(AuthorClaim.author_id).where(
            AuthorClaim.user_id == user_id,
            AuthorClaim.status == CLAIM_PENDING,
            AuthorClaim.author_id.in_(author_ids),
        )
    )
    return set(rows.scalars().all())


async def my_claims(db: AsyncSession, user_id: uuid.UUID) -> list[tuple[AuthorClaim, Author]]:
    """This reader's own "This is me" claims, newest first, each with its
    Author — a claim was otherwise invisible the moment it was filed: the
    button said "pending review" and there was nowhere to go and look
    (owner report, 23 Jul 2026). Only ever the caller's own rows."""
    rows = await db.execute(
        select(AuthorClaim, Author)
        .join(Author, Author.id == AuthorClaim.author_id)
        .where(AuthorClaim.user_id == user_id)
        .order_by(AuthorClaim.created_at.desc())
    )
    return [(claim, author) for claim, author in rows.all()]


async def withdraw_claim(db: AsyncSession, claim_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Take back one's own *unreviewed* claim — the accidental-tap escape hatch.

    Hard-deletes the row rather than marking it: nothing was ever decided, so
    the honest end state is "this was never asked", and it frees the
    (author_id, user_id) unique pair so a genuine claim can be filed later.
    Deliberately refuses a claim that has already been decided — allowing that
    would let a rejected claimant erase the rejection and re-file, which is
    exactly what `record_claim` declines to do by reopening.
    """
    claim = await db.get(AuthorClaim, claim_id)
    if claim is None or claim.user_id != user_id:
        # Someone else's claim is reported as missing, not forbidden — its
        # existence isn't the caller's business.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Claim not found"},
        )
    if claim.status != CLAIM_PENDING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "already_decided",
                "message": f"Claim is already {claim.status} and cannot be withdrawn",
            },
        )
    await db.delete(claim)
    await db.commit()


async def approve_claim(
    db: AsyncSession, claim_id: uuid.UUID, decided_by_user_id: uuid.UUID
) -> AuthorClaim:
    """Approve a pending claim — the *only* path that writes
    `authors.linked_user_id`, i.e. the only point the shared catalog changes.

    No endpoint calls this yet: approval is manual for now (owner decision —
    review UI comes later). The link is still guarded by `linked_user_id IS
    NULL`, so a claim approved after someone else's cannot quietly overwrite it.
    """
    claim = await db.get(AuthorClaim, claim_id)
    if claim is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Claim not found"},
        )
    if claim.status != CLAIM_PENDING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "already_decided", "message": f"Claim is already {claim.status}"},
        )
    result = await db.execute(
        update(Author)
        .where(Author.id == claim.author_id, Author.linked_user_id.is_(None))
        .values(linked_user_id=claim.user_id)
    )
    if result.rowcount == 0:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "already_linked",
                "message": "This author is already linked to another reader",
            },
        )
    claim.status = CLAIM_APPROVED
    claim.decided_at = datetime.now(UTC)
    claim.decided_by_user_id = decided_by_user_id
    await db.commit()
    await db.refresh(claim)
    return claim


async def reject_claim(
    db: AsyncSession, claim_id: uuid.UUID, decided_by_user_id: uuid.UUID
) -> AuthorClaim:
    """Reject a pending claim — leaves the shared row untouched, which is
    already what every reader but the claimant has been seeing all along."""
    claim = await db.get(AuthorClaim, claim_id)
    if claim is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Claim not found"},
        )
    if claim.status != CLAIM_PENDING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "already_decided", "message": f"Claim is already {claim.status}"},
        )
    claim.status = CLAIM_REJECTED
    claim.decided_at = datetime.now(UTC)
    claim.decided_by_user_id = decided_by_user_id
    await db.commit()
    await db.refresh(claim)
    return claim


async def create_publisher(db: AsyncSession, **fields: object) -> Publisher:
    """Publisher picker's "add new" flow — same get-or-create-by-name shape as
    create_author."""
    name = str(fields["name"]).strip()
    existing = (
        await db.execute(select(Publisher).where(Publisher.name.ilike(name)))
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    publisher = Publisher(**{**fields, "name": name})
    db.add(publisher)
    await db.flush()
    await slug_service.ensure_slug(db, publisher)
    await db.commit()
    await db.refresh(publisher)
    return publisher


async def _resolve_authors(
    db: AsyncSession, author_ids: list[uuid.UUID], author_names: list[str]
) -> list[Author]:
    """Author picker yields canonical ids; free-text / OpenLibrary yields names.
    Resolve ids first (skipping any that don't exist), then get-or-create the
    names, de-duplicating so an author referenced both ways isn't linked twice."""
    resolved: list[Author] = []
    seen: set[uuid.UUID] = set()
    for author_id in author_ids:
        author = await db.get(Author, author_id)
        if author is not None and author.id not in seen:
            resolved.append(author)
            seen.add(author.id)
    for name in author_names:
        author = await _get_or_create(db, Author, name)
        if author.id not in seen:
            resolved.append(author)
            seen.add(author.id)
    return resolved


async def _resolve_publisher(
    db: AsyncSession, publisher_id: uuid.UUID | None, publisher_name: str | None
) -> Publisher | None:
    if publisher_id is not None:
        publisher = await db.get(Publisher, publisher_id)
        if publisher is not None:
            return publisher
    if publisher_name:
        return await _get_or_create(db, Publisher, publisher_name)
    return None


async def _resolve_series(
    db: AsyncSession, series_id: uuid.UUID | None, series_name: str | None
) -> Series | None:
    """A picked series wins over a typed one. The name path stays because the
    CSV import, the OpenLibrary cache and the cover extractor all arrive with a
    string and no id — but every UI now sends the id, which is what stops
    "Ponniyin Selvan" and "ponniyin selvan " becoming two orderings."""
    if series_id is not None:
        series = await db.get(Series, series_id)
        if series is not None:
            # The merge check comes FIRST: merging soft-deletes the loser, so a
            # `deleted_at is None` guard in front of it would reject exactly the
            # rows the redirect exists for, and the app would silently drop the
            # series instead of landing on the canonical one.
            if series.merged_into_id is not None:
                survivor = await db.get(Series, series.merged_into_id)
                if survivor is not None and survivor.deleted_at is None:
                    return survivor
            elif series.deleted_at is None:
                return series
    if series_name:
        return await _get_or_create(db, Series, series_name)
    return None


async def set_work_series(
    db: AsyncSession,
    work: Work,
    series: Series | None,
    number: int | None,
    *,
    propagate: bool = True,
) -> int:
    """Put a Work at a position in a series (or take it out with series=None).

    Returns how many *other* Works in its translation group inherited the
    position. Book 3 is book 3 in every language, so the ordering is recorded
    once and shared: a translation with no series of its own follows the book
    it was translated from, and one that belongs to a different local series
    keeps what it has (never overwritten).
    """
    work.series_id = series.id if series else None
    work.series_number = number if series else None
    return await _propagate_series_to_group(db, work) if propagate else 0


async def _propagate_series_to_group(db: AsyncSession, work: Work) -> int:
    if work.translation_group_id is None:
        return 0
    siblings = (
        (
            await db.execute(
                select(Work).where(
                    Work.translation_group_id == work.translation_group_id,
                    Work.id != work.id,
                    Work.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    touched = 0
    for sibling in siblings:
        if sibling.series_id is None and work.series_id is not None:
            sibling.series_id = work.series_id
            sibling.series_number = work.series_number
            touched += 1
        elif sibling.series_id == work.series_id and sibling.series_number is None:
            # Same series, no number yet — the position is the shared fact.
            sibling.series_number = work.series_number
            touched += 1
    return touched


async def create_work_with_edition(
    db: AsyncSession, payload: WorkCreate, *, created_by: uuid.UUID | None = None
) -> Work:
    """The manual add/edit flow (S7b) — get-or-create every referenced
    author/publisher/genre/series, then create the Work + its first Edition.
    [created_by] credits the contributing reader for their score."""
    authors = await _resolve_authors(db, payload.author_ids, payload.author_names)
    translators = await _resolve_authors(db, payload.translator_ids, payload.translator_names)
    genres = [await _get_or_create(db, Genre, name) for name in payload.genre_names]
    publisher = await _resolve_publisher(db, payload.publisher_id, payload.publisher_name)
    series = await _resolve_series(db, payload.series_id, payload.series_name)

    work = Work(
        title=payload.title,
        subtitle=payload.subtitle,
        description=payload.description,
        language=payload.language,
        first_publish_year=payload.first_publish_year,
        form=payload.form,
        authors=authors,
        translators=translators,
        genres=genres,
        series_id=series.id if series else None,
        series_number=payload.series_number if series else None,
        created_by_user_id=created_by,
    )
    db.add(work)
    await db.flush()
    # `authors` is passed explicitly rather than read off the relationship —
    # see slug_service.work_extras. The slug disambiguates by author
    # ("chemmeen-thakazhi") before falling back to a meaningless counter.
    await slug_service.ensure_slug(db, work, extras=slug_service.work_extras(work, authors))

    # "Translated from" (T1/T4): join/create the original's translation group
    # and record the direction, in the same transaction as the create. A
    # non-resolving id is ignored rather than failing the whole add.
    if payload.original_work_id is not None:
        original = await db.get(Work, payload.original_work_id)
        if original is not None and original.deleted_at is None:
            group_id = original.translation_group_id or work.translation_group_id or uuid.uuid4()
            original.translation_group_id = group_id
            work.translation_group_id = group_id
            work.original_work_id = original.id
            # A translation added to a book that's in a series is at the same
            # position in it — inherited here so the ordering is entered once,
            # in whichever language someone happened to catalogue first.
            if work.series_id is None and original.series_id is not None:
                work.series_id = original.series_id
                work.series_number = original.series_number
            elif work.series_id is not None:
                await _propagate_series_to_group(db, work)

    edition = Edition(
        work_id=work.id,
        publisher_id=publisher.id if publisher else None,
        isbn=payload.isbn,
        language=payload.language,
        page_count=payload.page_count,
        pub_date=payload.pub_date,
        format=payload.format,
        cover_url=payload.cover_url,
        back_cover_url=payload.back_cover_url,
    )
    db.add(edition)
    await db.commit()
    return await get_work_or_404(db, work.id)


async def update_work(db: AsyncSession, work: Work, patch: WorkUpdate) -> Work:
    data = patch.model_dump(
        exclude_unset=True,
        exclude={
            "author_ids",
            "author_names",
            "translator_ids",
            "translator_names",
            "genre_names",
            "series_id",
            "series_name",
            "series_number",
        },
    )
    for field, value in data.items():
        setattr(work, field, value)
    # Series is set through the service, not by attribute assignment, because
    # putting a book at a position also places its translations there.
    if patch.series_id is not None or patch.series_name is not None:
        series = await _resolve_series(db, patch.series_id, patch.series_name)
        number = patch.series_number if patch.series_number is not None else work.series_number
        await set_work_series(db, work, series, number)
    elif patch.series_number is not None and work.series_id is not None:
        await set_work_series(db, work, await db.get(Series, work.series_id), patch.series_number)
    if patch.author_ids is not None or patch.author_names is not None:
        work.authors = await _resolve_authors(db, patch.author_ids or [], patch.author_names or [])
    if patch.translator_ids is not None or patch.translator_names is not None:
        work.translators = await _resolve_authors(
            db, patch.translator_ids or [], patch.translator_names or []
        )
    if patch.genre_names is not None:
        work.genres = [await _get_or_create(db, Genre, name) for name in patch.genre_names]
    await db.commit()
    return await get_work_or_404(db, work.id)


async def propose_or_apply_update(
    db: AsyncSession, work: Work, patch: WorkUpdate, user_id: uuid.UUID
) -> tuple[bool, Work, WorkRevision | None]:
    """Wiki-style moderation for catalog edits: the reader who contributed the
    Work (or anyone, for Works nobody owns — OpenLibrary imports and seeds)
    edits live; everyone else's change is queued as a pending [WorkRevision]
    for the contributor to approve. Returns (applied, live work, revision)."""
    if work.created_by_user_id is None or work.created_by_user_id == user_id:
        return True, await update_work(db, work, patch), None
    revision = WorkRevision(
        work_id=work.id,
        proposed_by_user_id=user_id,
        # mode="json" so UUIDs in author_ids serialise for the JSONB column.
        payload=patch.model_dump(exclude_unset=True, mode="json"),
    )
    db.add(revision)
    await db.commit()
    await db.refresh(revision)
    return False, work, revision


async def pending_revisions_for_approver(
    db: AsyncSession, approver_id: uuid.UUID
) -> list[tuple[WorkRevision, str, str | None]]:
    """The approval inbox — every pending revision to a Work this user
    contributed, oldest first, with the work title and the proposer's name."""
    stmt = (
        select(WorkRevision, Work.title, Profile.full_name)
        .join(Work, Work.id == WorkRevision.work_id)
        .outerjoin(Profile, Profile.id == WorkRevision.proposed_by_user_id)
        .where(
            WorkRevision.status == "pending",
            Work.created_by_user_id == approver_id,
            Work.deleted_at.is_(None),
        )
        .order_by(WorkRevision.created_at)
    )
    return [tuple(row) for row in (await db.execute(stmt)).all()]


async def decide_revision(
    db: AsyncSession,
    revision_id: uuid.UUID,
    approver_id: uuid.UUID,
    *,
    approve: bool,
    admin_override: bool = False,
) -> Work:
    """Approve (apply the queued WorkUpdate) or reject a pending revision.
    Only the Work's contributor may decide — unless `admin_override`, the
    escalation path the admin console uses to decide edits on seeded books that
    have no contributor, or ones a contributor has left sitting. Returns the
    live Work either way."""
    revision = await db.get(WorkRevision, revision_id)
    if revision is None or revision.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Revision not found"},
        )
    work = await get_work_or_404(db, revision.work_id)
    if not admin_override and work.created_by_user_id != approver_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "not_approver",
                "message": "Only the reader who added this book can review its edits",
            },
        )
    revision.status = "approved" if approve else "rejected"
    revision.decided_at = datetime.now(UTC)
    revision.decided_by_user_id = approver_id
    if approve:
        return await update_work(db, work, WorkUpdate(**revision.payload))
    await db.commit()
    return work


async def _merge_pair(
    db: AsyncSession, keep_id: uuid.UUID, absorb_id: uuid.UUID
) -> tuple[Work, Work]:
    """Validate a merge: both Works exist, are live, and are distinct."""
    if keep_id == absorb_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "same_work", "message": "Cannot merge a work into itself"},
        )
    keep = await db.get(Work, keep_id)
    absorb = await db.get(Work, absorb_id)
    for w in (keep, absorb):
        if w is None or w.deleted_at is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "not_found", "message": "Work not found"},
            )
    return keep, absorb


async def merge_preview(db: AsyncSession, keep_id: uuid.UUID, absorb_id: uuid.UUID) -> dict:
    """What a merge would move from `absorb` onto `keep` — shown before it runs,
    because merge touches other readers' library data and must not be a
    surprise. Library entries and reading sessions ride on the editions (they
    key off edition_id / library_entry_id), so moving the editions carries
    them; only ratings and reviews reference the Work directly."""
    keep, absorb = await _merge_pair(db, keep_id, absorb_id)

    async def n(model, work_id):  # noqa: ANN001
        return int(
            await db.scalar(select(func.count()).select_from(model).where(model.work_id == work_id))
            or 0
        )

    editions = await n(Edition, absorb_id)
    entries = int(
        await db.scalar(
            select(func.count())
            .select_from(LibraryEntry)
            .where(
                LibraryEntry.edition_id.in_(select(Edition.id).where(Edition.work_id == absorb_id))
            )
        )
        or 0
    )
    return {
        "keep": keep,
        "absorb": absorb,
        "editions": editions,
        "ratings": await n(Rating, absorb_id),
        "reviews": await n(Review, absorb_id),
        "library_entries": entries,
    }


async def merge_works(db: AsyncSession, keep_id: uuid.UUID, absorb_id: uuid.UUID) -> dict:
    """Merge `absorb` into `keep`: repoint its editions (Layer 1) and its
    ratings/reviews (Layer 2), fold its author/genre/translator links in
    without duplicating, then soft-delete it. One transaction. Layer-2 rows get
    a fresh server_seq so the change pulls to devices; the absorbed Work is
    soft-deleted (rule 3), never destroyed, so a mistaken merge is recoverable.
    """
    keep, absorb = await _merge_pair(db, keep_id, absorb_id)
    now = datetime.now(UTC)
    seq = text("nextval('sync_seq')")  # volatile → a distinct value per row

    await db.execute(
        update(Edition).where(Edition.work_id == absorb_id).values(work_id=keep_id, updated_at=now)
    )
    for model in (Rating, Review):
        await db.execute(
            update(model)
            .where(model.work_id == absorb_id)
            .values(work_id=keep_id, server_seq=seq, updated_at=now)
        )
    # Association tables: drop pairs that would duplicate on `keep`, move the rest.
    for join in (work_authors, work_genres, work_translators):
        col = "author_id" if join is not work_genres else "genre_id"
        await db.execute(
            text(
                f"DELETE FROM {join.name} a WHERE a.work_id = :absorb AND EXISTS "
                f"(SELECT 1 FROM {join.name} k WHERE k.work_id = :keep AND k.{col} = a.{col})"
            ),
            {"absorb": absorb_id, "keep": keep_id},
        )
        await db.execute(
            text(f"UPDATE {join.name} SET work_id = :keep WHERE work_id = :absorb"),
            {"keep": keep_id, "absorb": absorb_id},
        )
    # A translation that pointed at the absorbed work now points at the keeper.
    await db.execute(
        update(Work).where(Work.original_work_id == absorb_id).values(original_work_id=keep_id)
    )
    absorb.deleted_at = now
    absorb.updated_at = now
    await db.commit()
    return {
        "keep_id": str(keep_id),
        "absorb_id": str(absorb_id),
        "absorbed_title": absorb.title,
        "keep_title": keep.title,
    }


async def update_edition(db: AsyncSession, edition: Edition, patch: EditionUpdate) -> Edition:
    data = patch.model_dump(
        exclude_unset=True,
        exclude={
            "publisher_id",
            "publisher_name",
            "series_id",
            "series_name",
            "series_number",
        },
    )
    for field, value in data.items():
        setattr(edition, field, value)
    if patch.publisher_id is not None or patch.publisher_name is not None:
        publisher = await _resolve_publisher(db, patch.publisher_id, patch.publisher_name)
        if publisher is not None:
            edition.publisher_id = publisher.id
    # Series arriving on an edition patch is redirected to the work. App
    # installs in the field still send it here (it lived on the edition until
    # migration 000043) and their edits must keep landing somewhere real —
    # writing the edition's own column instead would put a second, divergent
    # answer next to the authoritative one.
    if (
        patch.series_id is not None
        or patch.series_name is not None
        or patch.series_number is not None
    ):
        work = await db.get(Work, edition.work_id)
        if work is not None:
            series = await _resolve_series(db, patch.series_id, patch.series_name)
            if series is None and patch.series_number is not None and work.series_id is not None:
                series = await db.get(Series, work.series_id)
            number = patch.series_number if patch.series_number is not None else work.series_number
            await set_work_series(db, work, series, number)
    await db.commit()
    return await get_edition_or_404(db, edition.id)


async def _load_work(db: AsyncSession, work_id: uuid.UUID) -> Work | None:
    """A plain `db.get()` returns the identity-mapped object as-is (ignoring
    `options=`) if it's already attached to this session — e.g. right after
    `db.add(work)` in the same request. `populate_existing()` forces a real
    reload with the eager-load options applied, every time."""
    stmt = select(Work).where(Work.id == work_id).options(*_WORK_JOINED)
    result = await db.execute(stmt.execution_options(populate_existing=True))
    return result.unique().scalar_one_or_none()


async def get_work_or_404(db: AsyncSession, work_id: uuid.UUID) -> Work:
    work = await _load_work(db, work_id)
    if work is None or work.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Work not found"},
        )
    return work


async def get_edition_or_404(db: AsyncSession, edition_id: uuid.UUID) -> Edition:
    stmt = (
        select(Edition)
        .where(Edition.id == edition_id)
        .options(joinedload(Edition.publisher), joinedload(Edition.series))
    )
    result = await db.execute(stmt.execution_options(populate_existing=True))
    edition = result.scalar_one_or_none()
    if edition is None or edition.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Edition not found"},
        )
    return edition


async def search_local(
    db: AsyncSession, query: str, limit: int = 20, *, fuzzy: bool = True
) -> list[Work]:
    """Search our own cached catalog (title, author name, or exact ISBN),
    typo-tolerant and relevance-ranked — 'Chemeen' finds Chemmeen, best match
    first. Two steps for correctness with the many-to-many author join:
    (1) matching work ids with their best score (grouped, GIN-index-served),
    (2) eager-load those works and keep the score order.

    [fuzzy]=False narrows to plain containment — the CSV import matcher takes
    the top hit as *the* match, so it must not be handed a merely-similar book.
    """
    q = query.strip()
    forms = isbn_util.variants(q)
    if forms:
        # EVERY equivalent form, not the one the reader happened to type. The
        # same book is 8126403454 on a 2005 printing and 9788126403455 on a
        # 2019 one; matching only the literal string means a reader holding the
        # older copy is told we have never heard of the book.
        #
        # More than one row can match — the catalogue may hold both forms on two
        # editions until the backfill or a merge collapses them — so this
        # returns works rather than a work, oldest edition first for a stable
        # order. (It also cannot use scalar_one_or_none any more, which would
        # now raise MultipleResultsFound on exactly that data.)
        stmt = (
            select(Edition)
            .where(Edition.isbn.in_(forms), Edition.deleted_at.is_(None))
            .order_by(Edition.created_at, Edition.id)
        )
        works: list[Work] = []
        seen: set[uuid.UUID] = set()
        for edition in (await db.execute(stmt)).scalars().all():
            if edition.work_id in seen:
                continue
            seen.add(edition.work_id)
            work = await _load_work(db, edition.work_id)
            if work is not None and work.deleted_at is None:
                works.append(work)
        return works
    if not q:
        return []

    if fuzzy:
        await _relax_word_similarity(db)
        match = or_(_fuzzy_match(Work.title, q), _fuzzy_match(Author.name, q))
        # Cross-script: the romanized query against the stored romanized
        # title/name, so "Kayary" finds "കയർ" and "ചെമ്മീൻ" finds "Chemmeen".
        qt = transliterate(q)
        if qt is not None:
            match = or_(
                match,
                _fuzzy_match(Work.title_translit, qt),
                _fuzzy_match(Author.name_translit, qt),
            )
        # …and the fold, which absorbs the spelling choices a romanized query
        # makes differently from ours ("chemmin" vs "chemmeen", "selvan" vs
        # "chelvan"). Cheap to add: same GIN trigram machinery, own column.
        qf = fold(q)
        if qf is not None:
            match = or_(
                match,
                _fuzzy_match(Work.title_fold, qf),
                _fuzzy_match(Author.name_fold, qf),
            )
    else:
        match = or_(Work.title.ilike(f"%{q}%"), Author.name.ilike(f"%{q}%"))
        qt = qf = None
    # Postgres's greatest() ignores NULLs, so works without authors (outer
    # join) still rank by their title score.
    best = [_rank(Work.title, q), _rank(Author.name, q)]
    if qt is not None:
        best += [_rank(Work.title_translit, qt), _rank(Author.name_translit, qt)]
    if qf is not None:
        best += [_rank(Work.title_fold, qf), _rank(Author.name_fold, qf)]
    score = func.max(func.greatest(*best))
    ranked = (
        select(Work.id, score.label("score"))
        .select_from(Work)
        .outerjoin(Work.authors)
        .where(Work.deleted_at.is_(None), match)
        .group_by(Work.id)
        .order_by(score.desc())
        .limit(limit)
    )
    ordered_ids = [row.id for row in (await db.execute(ranked)).all()]
    if not ordered_ids:
        return []

    stmt = (
        select(Work)
        .options(*_SUMMARY_OPTIONS)
        .where(Work.id.in_(ordered_ids))
        .execution_options(populate_existing=True)
    )
    by_id = {w.id: w for w in (await db.execute(stmt)).scalars().all()}
    return [by_id[i] for i in ordered_ids if i in by_id]


async def find_similar_works(db: AsyncSession, title: str, limit: int = 5) -> list[Work]:
    """Typo-tolerant "is this book already in the catalog?" for the add-book
    form (S7b). Matches by trigram similarity so 'Chemeen' still finds
    'Chemmeen', plus containment for partial typing — every predicate here is
    accelerated by the GIN trigram index (migration 000018):

    - `title % q`   — pg_trgm similarity above the GUC threshold (default 0.3)
    - `q <% title`  — word_similarity: the typed text vs the best-matching
                      span, so 'Harry Pott' matches a long full title
    - `ILIKE %q%`   — plain containment (also trigram-index-served)

    Ranked by the best of similarity/word_similarity, best first. Trigrams are
    plain character windows, so Malayalam and every other script work as-is.
    """
    q = title.strip()
    if len(q) < 3:
        return []

    # Duplicate detection is cross-script too — typing "Kayar" while "കയർ"
    # already exists must surface the existing book.
    await _relax_word_similarity(db)
    qt = transliterate(q)
    qf = fold(q)
    score = func.greatest(
        func.similarity(Work.title, q),
        func.word_similarity(q, Work.title),
        *([_rank(Work.title_translit, qt)] if qt is not None else []),
        *([_rank(Work.title_fold, qf)] if qf is not None else []),
    )
    match = or_(
        Work.title.ilike(f"%{q}%"),
        Work.title.op("%")(q),
        literal(q).op("<%")(Work.title),
    )
    if qt is not None:
        match = or_(match, _fuzzy_match(Work.title_translit, qt))
    if qf is not None:
        match = or_(match, _fuzzy_match(Work.title_fold, qf))
    stmt = (
        select(Work)
        .options(*_SUMMARY_OPTIONS)
        .where(Work.deleted_at.is_(None), match)
        .order_by(score.desc(), Work.title)
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


# The Length filter's buckets. The bounds follow the query readers actually
# type ("short books under 200 pages" — a documented search surge since the
# BookTok #ShortReads wave): short < 200, medium 200–399, long ≥ 400. A work
# qualifies when ANY live edition's page_count lands in the bucket, because
# counts differ per printing and the reader is asking about the book, not one
# ISBN. Values are the API's `length` vocabulary — endpoints validate against
# these keys.
LENGTH_BOUNDS: dict[str, tuple[int, int | None]] = {
    "short": (1, 200),
    "medium": (200, 400),
    "long": (400, None),
}


def length_filter(length: str):  # noqa: ANN201 — SQLAlchemy boolean clause
    """EXISTS over live editions whose page_count falls in the named bucket."""
    lo, hi = LENGTH_BOUNDS[length]
    conds = [Edition.deleted_at.is_(None), Edition.page_count >= lo]
    if hi is not None:
        conds.append(Edition.page_count < hi)
    return Work.editions.any(and_(*conds))


async def browse_works(
    db: AsyncSession,
    limit: int,
    offset: int,
    languages: list[str] | None = None,
    form: str | None = None,
    genre: str | None = None,
    length: str | None = None,
    series: uuid.UUID | None = None,
    sort: str = "title",
) -> list[Work]:
    """The Discover/browse screen — catalog works, paged, with optional
    language(s) / form (Type) / genre / length filters and sort (title /
    newest / oldest / author / top-rated / recently added). Layer 1 is
    server-authoritative, so this reads straight from our catalog.
    `languages` is a list because the app's default filter is the reader's
    preferred languages — usually more than one."""
    stmt = select(Work).options(*_SUMMARY_OPTIONS).where(Work.deleted_at.is_(None))
    if languages:
        stmt = stmt.where(Work.language.in_(languages))
    if form:
        stmt = stmt.where(Work.form == form)
    if genre:
        # EXISTS rather than a join: a work can carry several genres, and a
        # join would fan it out into one row per match (and collide with the
        # author sort's own join/group_by below).
        stmt = stmt.where(
            Work.genres.any(func.lower(Genre.name) == genre.strip().lower()),
        )
    if length:
        stmt = stmt.where(length_filter(length))
    if series is not None:
        stmt = stmt.where(Work.series_id == series)

    if sort == "series":
        # Reading order — the only sort that makes sense once a series filter
        # is on, and meaningless without one, so it is offered with it.
        return list(
            (
                await db.execute(
                    stmt.order_by(
                        Work.series_number.asc().nullslast(),
                        Work.first_publish_year.asc().nullslast(),
                        Work.title.asc(),
                    )
                    .limit(limit)
                    .offset(offset)
                )
            )
            .unique()
            .scalars()
            .all()
        )

    if sort == "rating":
        # "Best X" is the highest-intent browse there is, so the order is the
        # live average over the ratings table (Work.aggregate_rating is never
        # written — see review_service.rating_summary). Ties break toward the
        # book more readers rated, then title for a stable page walk.
        # SCALE: denormalize onto Work if this grouped join ever shows in
        # traces; fine at catalogue size.
        rated = (
            select(
                Rating.work_id.label("work_id"),
                func.avg(Rating.value).label("avg_rating"),
                func.count().label("rating_count"),
            )
            .where(Rating.deleted_at.is_(None))
            .group_by(Rating.work_id)
            .subquery()
        )
        stmt = stmt.outerjoin(rated, rated.c.work_id == Work.id).order_by(
            rated.c.avg_rating.desc().nullslast(),
            rated.c.rating_count.desc().nullslast(),
            Work.title.asc(),
        )
    elif sort == "added":
        # "What's new here" — arrival in the catalogue, not publication year
        # (year_desc already covers that). Keeps the shelf feeling alive.
        stmt = stmt.order_by(Work.created_at.desc(), Work.title.asc())
    elif sort == "author":
        # One row per work, ordered by its earliest author name. group_by the
        # PK collapses the M2M join without a DISTINCT-vs-ORDER-BY conflict.
        stmt = (
            stmt.outerjoin(Work.authors)
            .group_by(Work.id)
            .order_by(func.min(Author.name).asc().nullslast(), Work.title.asc())
        )
    elif sort == "year_desc":
        stmt = stmt.order_by(Work.first_publish_year.desc().nullslast(), Work.title.asc())
    elif sort == "year_asc":
        stmt = stmt.order_by(Work.first_publish_year.asc().nullslast(), Work.title.asc())
    else:
        stmt = stmt.order_by(Work.title.asc())

    stmt = stmt.limit(limit).offset(offset).execution_options(populate_existing=True)
    return list((await db.execute(stmt)).scalars().all())


async def catalog_languages(db: AsyncSession) -> list[str]:
    """Distinct non-null work languages — powers the browse language filter."""
    stmt = (
        select(Work.language)
        .where(Work.deleted_at.is_(None), Work.language.is_not(None))
        .distinct()
        .order_by(Work.language)
    )
    return [row for row in (await db.execute(stmt)).scalars().all() if row]


async def catalog_forms(db: AsyncSession) -> list[str]:
    """Distinct literary forms actually present in the catalog — the browse
    Type filter offers only what it can return, not the whole vocabulary."""
    stmt = select(Work.form).where(Work.deleted_at.is_(None), Work.form.is_not(None)).distinct()
    present = {row for row in (await db.execute(stmt)).scalars().all() if row}
    # Vocabulary order first (Novel/Short stories/Poetry lead — that's how a
    # reader scans them), then anyone's custom forms alphabetically after. The
    # custom ones must not be dropped: a reader who typed "Novella" has to be
    # able to filter by it.
    known = [f for f in WORK_FORMS if f in present]
    custom = sorted(present - set(WORK_FORMS))
    return known + custom


async def catalog_genres(db: AsyncSession) -> list[tuple[str, int]]:
    """Genres carried by at least one live work, with how many works each has —
    (name, work_count), commonest first. Genres nothing uses (a typo, an
    emptied work) would be dead ends, so they're excluded.

    The count isn't decoration: the add form's genre picker shows it so a
    reader can see "Science fiction · 128" and not invent "Sci-fi" beside it
    (mockup M11). Genres get no case-folding on write the way Type does
    (`normalize_form`), so that picker is the only thing standing between the
    shared facet and three spellings of one genre."""
    count = func.count(work_genres.c.work_id)
    stmt = (
        select(Genre.name, count)
        .join(work_genres, work_genres.c.genre_id == Genre.id)
        .join(Work, Work.id == work_genres.c.work_id)
        .where(Work.deleted_at.is_(None))
        .group_by(Genre.name)
        .order_by(count.desc(), Genre.name)
    )
    return [(name, total) for name, total in (await db.execute(stmt)).all() if name]


async def browse_authors(
    db: AsyncSession, limit: int, offset: int, *, popular: bool = False
) -> list[Author]:
    stmt = select(Author).where(Author.deleted_at.is_(None))
    if popular:
        # Suggestions for the author picker: the authors carrying the most works
        # first (a blank picker should surface the catalog's real regulars, not
        # whoever happens to sort first alphabetically). Outer-join so authors
        # with zero works still appear, just last.
        stmt = (
            stmt.outerjoin(work_authors, work_authors.c.author_id == Author.id)
            .group_by(Author.id)
            .order_by(func.count(work_authors.c.work_id).desc(), Author.name)
        )
    else:
        stmt = stmt.order_by(Author.name)
    stmt = stmt.limit(limit).offset(offset)
    return list((await db.execute(stmt)).scalars().all())


async def browse_publishers(
    db: AsyncSession, limit: int, offset: int, *, popular: bool = False
) -> list[Publisher]:
    stmt = select(Publisher).where(Publisher.deleted_at.is_(None))
    if popular:
        # Publisher-picker suggestions — most editions first, same rationale as
        # browse_authors above.
        stmt = (
            stmt.outerjoin(Edition, Edition.publisher_id == Publisher.id)
            .group_by(Publisher.id)
            .order_by(func.count(Edition.id).desc(), Publisher.name)
        )
    else:
        stmt = stmt.order_by(Publisher.name)
    stmt = stmt.limit(limit).offset(offset)
    return list((await db.execute(stmt)).scalars().all())


async def browse_series(
    db: AsyncSession, limit: int, offset: int, *, popular: bool = False
) -> list[tuple[Series, int]]:
    """Series with how many books each holds — the browse list and the picker's
    suggestions both need the count, because "Malgudi · 4 books" is what tells
    a real series apart from the empty row a typo left behind."""
    counted = (
        select(Work.series_id, func.count(Work.id).label("books"))
        .where(Work.deleted_at.is_(None), Work.series_id.is_not(None))
        .group_by(Work.series_id)
        .subquery()
    )
    books = func.coalesce(counted.c.books, 0)
    stmt = (
        select(Series, books)
        .outerjoin(counted, counted.c.series_id == Series.id)
        .where(Series.deleted_at.is_(None), Series.merged_into_id.is_(None))
    )
    stmt = stmt.order_by(books.desc(), Series.name) if popular else stmt.order_by(Series.name)
    rows = (await db.execute(stmt.limit(limit).offset(offset))).all()
    return [(series, int(count or 0)) for series, count in rows]


async def series_book_counts(db: AsyncSession, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """How many books each of these series holds."""
    if not ids:
        return {}
    rows = (
        await db.execute(
            select(Work.series_id, func.count(Work.id))
            .where(Work.series_id.in_(ids), Work.deleted_at.is_(None))
            .group_by(Work.series_id)
        )
    ).all()
    return {series_id: int(count) for series_id, count in rows}


async def create_series(db: AsyncSession, **fields: object) -> Series:
    """The picker's "add new" — get-or-create by name, so two readers adding
    the same series a minute apart get one row, not a duplicate to merge."""
    name = str(fields["name"]).strip()
    existing = (
        await db.execute(select(Series).where(Series.name.ilike(name), Series.deleted_at.is_(None)))
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    series = Series(**{**fields, "name": name})
    db.add(series)
    await db.flush()
    await slug_service.ensure_slug(db, series)
    await db.commit()
    await db.refresh(series)
    return series


async def series_works(db: AsyncSession, series_id: uuid.UUID) -> list[Work]:
    """Everything in the series, in reading order. Unnumbered books sort last
    (by year, then title) rather than jumping to the front as NULLs do."""
    stmt = (
        select(Work)
        .options(*_SUMMARY_OPTIONS)
        .where(Work.series_id == series_id, Work.deleted_at.is_(None))
        .order_by(
            Work.series_number.asc().nullslast(),
            Work.first_publish_year.asc().nullslast(),
            Work.title.asc(),
        )
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).unique().scalars().all())


def _name_match_and_rank(name_col, translit_col, fold_col, q: str):  # noqa: ANN001
    """Fuzzy predicate + rank over a name column, its romanized twin and its
    spelling-insensitive fold — shared by the author/publisher/series searches
    so all three are cross-script and spelling-tolerant."""
    qt = transliterate(q)
    qf = fold(q)
    match = _fuzzy_match(name_col, q)
    ranks = [_rank(name_col, q)]
    if qt is not None:
        match = or_(match, _fuzzy_match(translit_col, qt))
        ranks.append(_rank(translit_col, qt))
    if qf is not None:
        match = or_(match, _fuzzy_match(fold_col, qf))
        ranks.append(_rank(fold_col, qf))
    return match, func.greatest(*ranks)


async def search_authors(db: AsyncSession, query: str, limit: int = 10) -> list[Author]:
    """Author search for the global search (S4) and the add/edit form's
    typeahead — typo-tolerant ('Thakazi' finds Thakazhi) and cross-script
    ('Thakazhi' finds 'തകഴി'), best match first."""
    q = query.strip()
    if not q:
        return []
    await _relax_word_similarity(db)
    match, rank = _name_match_and_rank(Author.name, Author.name_translit, Author.name_fold, q)
    # deleted_at also covers merged duplicates (merge soft-deletes the loser) —
    # without this filter a folded row kept surfacing in search and typeaheads.
    stmt = (
        select(Author)
        .where(match, Author.deleted_at.is_(None))
        .order_by(rank.desc(), Author.name)
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


async def search_publishers(db: AsyncSession, query: str, limit: int = 10) -> list[Publisher]:
    """Publisher search — same fuzzy + ranked shape as search_authors."""
    q = query.strip()
    if not q:
        return []
    await _relax_word_similarity(db)
    match, rank = _name_match_and_rank(
        Publisher.name, Publisher.name_translit, Publisher.name_fold, q
    )
    stmt = (
        select(Publisher)
        .where(match, Publisher.deleted_at.is_(None))
        .order_by(rank.desc(), Publisher.name)
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


async def search_series(db: AsyncSession, query: str, limit: int = 10) -> list[Series]:
    """Series search for the picker — same fuzzy, cross-script shape as the
    author and publisher searches. Without it a reader typing "aithihyamala"
    would never find "ഐതിഹ്യമാല" and would create a second series beside it,
    which is how the free-text field kept splitting one ordering in two."""
    q = query.strip()
    if not q:
        return []
    await _relax_word_similarity(db)
    match, rank = _name_match_and_rank(Series.name, Series.name_translit, Series.name_fold, q)
    stmt = (
        select(Series)
        .where(match, Series.deleted_at.is_(None))
        .order_by(rank.desc(), Series.name)
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


async def find_or_fetch_by_isbn(
    db: AsyncSession, ol_client: OpenLibraryClient, isbn: str
) -> Edition | None:
    """ISBN scan flow (S7): local match first, then OpenLibrary, caching
    whatever we find so the next scan of the same ISBN never leaves the
    database.

    The local match tries every equivalent form, so scanning the ISBN-10 barcode
    on an older printing finds the row we catalogued under its ISBN-13 instead of
    spending an OpenLibrary round trip and creating a duplicate edition of a book
    we already have.
    """
    forms = isbn_util.variants(isbn) or [isbn.replace("-", "").strip()]
    stmt = (
        select(Edition)
        .where(Edition.isbn.in_(forms), Edition.deleted_at.is_(None))
        .order_by(Edition.created_at, Edition.id)
        .limit(1)
    )
    existing = (await db.execute(stmt)).scalars().first()
    if existing is not None:
        return existing

    # OpenLibrary is asked with the form the reader supplied — it resolves both
    # and knows about editions we don't — but whatever comes back is STORED
    # canonically, so the catalogue converges on ISBN-13 as rows are added.
    lookup_isbn = forms[0]
    raw = await ol_client.lookup_isbn(lookup_isbn)
    if raw is None:
        return None
    normalized = normalize_isbn_lookup(raw, isbn_util.canonical(lookup_isbn) or lookup_isbn)

    work_payload = WorkCreate(
        title=normalized["title"],
        subtitle=normalized["subtitle"],
        first_publish_year=normalized["first_publish_year"],
        author_names=normalized["author_names"],
        publisher_name=normalized["publisher_name"],
        isbn=normalized["isbn"],
        page_count=normalized["page_count"],
        pub_date=normalized["pub_date"],
        cover_url=normalized["cover_url"],
    )
    work = await create_work_with_edition(db, work_payload)
    work.external_source = normalized["external_source"]
    work.external_id = normalized["external_id"]
    edition = work.editions[0]
    edition.external_source = normalized["external_source"]
    edition.external_id = normalized["external_id"]
    await db.commit()
    return edition


async def create_edition(db: AsyncSession, work: Work, payload: EditionCreate) -> Edition:
    """Attach another edition (printing/ISBN) to an existing Work — same book,
    different physical copy. Mirrors the edition half of create_work_with_edition
    but leaves the Work (title/authors/genres) untouched."""
    publisher = await _resolve_publisher(db, payload.publisher_id, payload.publisher_name)
    # A series arriving with a new printing describes the *book*, not the
    # printing — so it lands on the Work, the same as on the edit path. An app
    # install that predates migration 000043 sends it here.
    series = await _resolve_series(db, payload.series_id, payload.series_name)
    if series is not None or payload.series_number is not None:
        target = series or (await db.get(Series, work.series_id) if work.series_id else None)
        number = payload.series_number if payload.series_number is not None else work.series_number
        await set_work_series(db, work, target, number)

    edition = Edition(
        work_id=work.id,
        publisher_id=publisher.id if publisher else None,
        isbn=payload.isbn,
        # An edition inherits the Work's language unless told otherwise.
        language=payload.language or work.language,
        page_count=payload.page_count,
        pub_date=payload.pub_date,
        format=payload.format,
        cover_url=payload.cover_url,
        back_cover_url=payload.back_cover_url,
    )
    db.add(edition)
    await db.commit()
    return await get_edition_or_404(db, edition.id)


async def translation_siblings(db: AsyncSession, work: Work) -> list[Work]:
    """The *other* Works sharing this one's translation_group_id — what the book
    page lists under "Also in other languages". Empty when the Work isn't
    linked to any translation."""
    if work.translation_group_id is None:
        return []
    stmt = (
        select(Work)
        .where(
            Work.translation_group_id == work.translation_group_id,
            Work.id != work.id,
            Work.deleted_at.is_(None),
        )
        .options(*_SUMMARY_OPTIONS)
        .order_by(Work.title)
    )
    return list((await db.execute(stmt)).unique().scalars().all())


async def link_translation(
    db: AsyncSession, work: Work, other_work: Work, relation: str = "sibling"
) -> None:
    """Link two Works as translations of one another. Reuses an existing
    translation_group_id if either side already has one, so linking a third
    translation later just joins the same group.

    [relation] adds the direction on top of the undirected group:
    "original" — other_work is work's original; "translation" — other_work is
    a translation of work; "sibling" — direction unknown, group-link only."""
    group_id = work.translation_group_id or other_work.translation_group_id or uuid.uuid4()
    work.translation_group_id = group_id
    other_work.translation_group_id = group_id
    if relation == "original":
        work.original_work_id = other_work.id
    elif relation == "translation":
        other_work.original_work_id = work.id
    # Book 3 is book 3 in every language, so joining a group joins its
    # position: whichever side already has one lends it to the side that
    # doesn't. A translation that belongs to a different local series keeps
    # what it has — _propagate_series_to_group never overwrites.
    for source in (work, other_work):
        if source.series_id is not None:
            await _propagate_series_to_group(db, source)
    await db.commit()


async def work_summary_row(db: AsyncSession, work_id: uuid.UUID) -> Work | None:
    """One Work loaded with the summary options — for WorkOut.original."""
    stmt = (
        select(Work).where(Work.id == work_id, Work.deleted_at.is_(None)).options(*_SUMMARY_OPTIONS)
    )
    return (await db.execute(stmt)).unique().scalar_one_or_none()


async def translation_group_rating(db: AsyncSession, work: Work) -> float | None:
    """Each translation is its own Work with its own independent rating pool
    (product decision, 5 Jul 2026 — a translation is its own literary object,
    so its reviews shouldn't inherit the original's). This is the *display*
    aggregate shown alongside a Work's own rating — "4.2 across all
    translations" — averaged over every Work sharing `translation_group_id`,
    computed at read time rather than stored, since it depends on sibling
    Works whose own ratings can change independently. Returns None until at
    least one Work in the group has a real rating (Phase 3)."""
    if work.translation_group_id is None:
        return None
    stmt = select(Work.aggregate_rating).where(
        Work.translation_group_id == work.translation_group_id,
        Work.aggregate_rating.is_not(None),
    )
    ratings = (await db.execute(stmt)).scalars().all()
    if not ratings:
        return None
    return sum(ratings) / len(ratings)


async def author_works(db: AsyncSession, author_id: uuid.UUID) -> list[Work]:
    stmt = (
        select(Work)
        .options(*_SUMMARY_OPTIONS)
        .join(Work.authors)
        .where(Author.id == author_id, Work.deleted_at.is_(None))
        .order_by(Work.first_publish_year)
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).scalars().all())


async def works_by_linked_author(db: AsyncSession, user_id: uuid.UUID) -> list[Work]:
    """Every catalog Work whose author is linked to this profile — the
    "Works" tab on a reader's public profile. Same shape as `author_works`,
    just keyed by `linked_user_id` instead of a specific Author row (a reader
    can be self-linked to more than one Author, e.g. a pen name)."""
    stmt = (
        select(Work)
        .options(*_SUMMARY_OPTIONS)
        .join(Work.authors)
        .where(Author.linked_user_id == user_id, Work.deleted_at.is_(None))
        .order_by(Work.first_publish_year)
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).scalars().all())


async def publisher_works(db: AsyncSession, publisher_id: uuid.UUID) -> list[Work]:
    stmt = (
        select(Work)
        .options(*_SUMMARY_OPTIONS)
        .join(Edition, Edition.work_id == Work.id)
        .where(Edition.publisher_id == publisher_id, Work.deleted_at.is_(None))
        .distinct()
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).scalars().all())
