"""Shared catalog (Layer 1) business logic — server-authoritative works, editions,
authors, publishers, genres, series. Case-insensitive get-or-create dedupe, ISBN
lookup with OpenLibrary cache-on-first-use, and tuned eager-loading for detail vs.
list reads. Catalog rows carry no client-generated id; user contributions land here
via the API when online (CLAUDE.md rule 2)."""

import re
import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, literal, or_, select, text, update
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
    Profile,
    Publisher,
    Series,
    Work,
    WorkRevision,
    work_authors,
    work_genres,
)
from app.schemas.catalog import (
    WORK_FORMS,
    EditionCreate,
    EditionUpdate,
    WorkCreate,
    WorkUpdate,
)
from app.services.openlibrary_client import OpenLibraryClient, normalize_isbn_lookup
from app.services.translit import fold, transliterate

_ISBN_RE = re.compile(r"^[0-9]{9}[0-9X]$|^[0-9]{13}$")

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


def looks_like_isbn(query: str) -> bool:
    return bool(_ISBN_RE.match(query.replace("-", "").strip()))


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
    series = await _get_or_create(db, Series, payload.series_name) if payload.series_name else None

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
        created_by_user_id=created_by,
    )
    db.add(work)
    await db.flush()

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

    edition = Edition(
        work_id=work.id,
        publisher_id=publisher.id if publisher else None,
        series_id=series.id if series else None,
        series_number=payload.series_number,
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
        exclude={"author_ids", "author_names", "translator_ids", "translator_names", "genre_names"},
    )
    for field, value in data.items():
        setattr(work, field, value)
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
    db: AsyncSession, revision_id: uuid.UUID, approver_id: uuid.UUID, *, approve: bool
) -> Work:
    """Approve (apply the queued WorkUpdate) or reject a pending revision.
    Only the Work's contributor may decide. Returns the live Work either way."""
    revision = await db.get(WorkRevision, revision_id)
    if revision is None or revision.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Revision not found"},
        )
    work = await get_work_or_404(db, revision.work_id)
    if work.created_by_user_id != approver_id:
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


async def update_edition(db: AsyncSession, edition: Edition, patch: EditionUpdate) -> Edition:
    data = patch.model_dump(
        exclude_unset=True, exclude={"publisher_id", "publisher_name", "series_name"}
    )
    for field, value in data.items():
        setattr(edition, field, value)
    if patch.publisher_id is not None or patch.publisher_name is not None:
        publisher = await _resolve_publisher(db, patch.publisher_id, patch.publisher_name)
        if publisher is not None:
            edition.publisher_id = publisher.id
    if patch.series_name is not None:
        series = await _get_or_create(db, Series, patch.series_name)
        edition.series_id = series.id
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
    if looks_like_isbn(q):
        stmt = select(Edition).where(Edition.isbn == q.replace("-", "").strip())
        edition = (await db.execute(stmt)).scalar_one_or_none()
        if edition is None:
            return []
        work = await _load_work(db, edition.work_id)
        return [work] if work else []
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


async def browse_works(
    db: AsyncSession,
    limit: int,
    offset: int,
    language: str | None = None,
    form: str | None = None,
    genre: str | None = None,
    sort: str = "title",
) -> list[Work]:
    """The Discover/browse screen — catalog works, paged, with optional
    language / form (Type) / genre filters and sort (title / newest / oldest /
    author). Layer 1 is server-authoritative, so this reads straight from our
    catalog."""
    stmt = select(Work).options(*_SUMMARY_OPTIONS).where(Work.deleted_at.is_(None))
    if language:
        stmt = stmt.where(Work.language == language)
    if form:
        stmt = stmt.where(Work.form == form)
    if genre:
        # EXISTS rather than a join: a work can carry several genres, and a
        # join would fan it out into one row per match (and collide with the
        # author sort's own join/group_by below).
        stmt = stmt.where(
            Work.genres.any(func.lower(Genre.name) == genre.strip().lower()),
        )

    if sort == "author":
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


def _name_match_and_rank(name_col, translit_col, fold_col, q: str):  # noqa: ANN001
    """Fuzzy predicate + rank over a name column, its romanized twin and its
    spelling-insensitive fold — shared by the author/publisher searches so both
    are cross-script and spelling-tolerant."""
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
    stmt = select(Author).where(match).order_by(rank.desc(), Author.name).limit(limit)
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
    stmt = select(Publisher).where(match).order_by(rank.desc(), Publisher.name).limit(limit)
    return list((await db.execute(stmt)).scalars().all())


async def find_or_fetch_by_isbn(
    db: AsyncSession, ol_client: OpenLibraryClient, isbn: str
) -> Edition | None:
    """ISBN scan flow (S7): local match first, then OpenLibrary, caching
    whatever we find so the next scan of the same ISBN never leaves the
    database."""
    clean_isbn = isbn.replace("-", "").strip()
    stmt = select(Edition).where(Edition.isbn == clean_isbn)
    existing = (await db.execute(stmt)).scalar_one_or_none()
    if existing is not None:
        return existing

    raw = await ol_client.lookup_isbn(clean_isbn)
    if raw is None:
        return None
    normalized = normalize_isbn_lookup(raw, clean_isbn)

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
    series = await _get_or_create(db, Series, payload.series_name) if payload.series_name else None

    edition = Edition(
        work_id=work.id,
        publisher_id=publisher.id if publisher else None,
        series_id=series.id if series else None,
        series_number=payload.series_number,
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
