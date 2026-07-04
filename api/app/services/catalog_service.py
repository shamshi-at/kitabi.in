import re
import uuid

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload

from app.models import Author, Edition, Genre, Publisher, Series, Work
from app.schemas.catalog import EditionUpdate, WorkCreate, WorkUpdate
from app.services.openlibrary_client import OpenLibraryClient, normalize_isbn_lookup

_ISBN_RE = re.compile(r"^[0-9]{9}[0-9X]$|^[0-9]{13}$")

# Explicit eager loading everywhere a Work is fetched for serialization.
# Relying on the models' default `lazy=` strategy is NOT enough on its own in
# async SQLAlchemy — whether it actually eager-loads depends on the access
# path (get() vs select() vs refresh()), and a plain attribute access that
# falls through to a lazy load outside an awaited call raises MissingGreenlet.
_WORK_OPTIONS = (
    selectinload(Work.authors),
    selectinload(Work.genres),
    selectinload(Work.editions).options(joinedload(Edition.publisher), joinedload(Edition.series)),
)


def looks_like_isbn(query: str) -> bool:
    return bool(_ISBN_RE.match(query.replace("-", "").strip()))


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


async def create_work_with_edition(db: AsyncSession, payload: WorkCreate) -> Work:
    """The manual add/edit flow (S7b) — get-or-create every referenced
    author/publisher/genre/series, then create the Work + its first Edition."""
    authors = [await _get_or_create(db, Author, name) for name in payload.author_names]
    genres = [await _get_or_create(db, Genre, name) for name in payload.genre_names]
    publisher = (
        await _get_or_create(db, Publisher, payload.publisher_name)
        if payload.publisher_name
        else None
    )
    series = await _get_or_create(db, Series, payload.series_name) if payload.series_name else None

    work = Work(
        title=payload.title,
        subtitle=payload.subtitle,
        description=payload.description,
        language=payload.language,
        first_publish_year=payload.first_publish_year,
        authors=authors,
        genres=genres,
    )
    db.add(work)
    await db.flush()

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
    )
    db.add(edition)
    await db.commit()
    return await get_work_or_404(db, work.id)


async def update_work(db: AsyncSession, work: Work, patch: WorkUpdate) -> Work:
    data = patch.model_dump(exclude_unset=True, exclude={"author_names", "genre_names"})
    for field, value in data.items():
        setattr(work, field, value)
    if patch.author_names is not None:
        work.authors = [await _get_or_create(db, Author, name) for name in patch.author_names]
    if patch.genre_names is not None:
        work.genres = [await _get_or_create(db, Genre, name) for name in patch.genre_names]
    await db.commit()
    return await get_work_or_404(db, work.id)


async def update_edition(db: AsyncSession, edition: Edition, patch: EditionUpdate) -> Edition:
    data = patch.model_dump(exclude_unset=True, exclude={"publisher_name", "series_name"})
    for field, value in data.items():
        setattr(edition, field, value)
    if patch.publisher_name is not None:
        publisher = await _get_or_create(db, Publisher, patch.publisher_name)
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
    stmt = select(Work).where(Work.id == work_id).options(*_WORK_OPTIONS)
    result = await db.execute(stmt.execution_options(populate_existing=True))
    return result.scalar_one_or_none()


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


async def search_local(db: AsyncSession, query: str, limit: int = 20) -> list[Work]:
    """Search our own cached catalog first (title, author name, or exact
    ISBN) — cache-on-first-use means popular searches get faster and cheaper
    over time as more of the catalog is already local."""
    if looks_like_isbn(query):
        stmt = select(Edition).where(Edition.isbn == query.replace("-", "").strip())
        edition = (await db.execute(stmt)).scalar_one_or_none()
        if edition is None:
            return []
        work = await _load_work(db, edition.work_id)
        return [work] if work else []

    stmt = (
        select(Work)
        .options(*_WORK_OPTIONS)
        .outerjoin(Work.authors)
        .where(
            Work.deleted_at.is_(None),
            or_(Work.title.ilike(f"%{query}%"), Author.name.ilike(f"%{query}%")),
        )
        .distinct()
        .limit(limit)
        .execution_options(populate_existing=True)
    )
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


async def link_translation(db: AsyncSession, work: Work, other_work: Work) -> None:
    """[WIRED] — link two Works as translations of one another. Reuses an
    existing translation_group_id if either side already has one, so linking
    a third translation later just joins the same group."""
    group_id = work.translation_group_id or other_work.translation_group_id or uuid.uuid4()
    work.translation_group_id = group_id
    other_work.translation_group_id = group_id
    await db.commit()


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
        .options(*_WORK_OPTIONS)
        .join(Work.authors)
        .where(Author.id == author_id, Work.deleted_at.is_(None))
        .order_by(Work.first_publish_year)
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).scalars().all())


async def publisher_works(db: AsyncSession, publisher_id: uuid.UUID) -> list[Work]:
    stmt = (
        select(Work)
        .options(*_WORK_OPTIONS)
        .join(Edition, Edition.work_id == Work.id)
        .where(Edition.publisher_id == publisher_id, Work.deleted_at.is_(None))
        .distinct()
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).scalars().all())
