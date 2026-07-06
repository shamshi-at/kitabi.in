import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import CurrentUser, DbSession
from app.models import Author, Publisher
from app.schemas.catalog import (
    AuthorCreate,
    AuthorOut,
    AuthorWorksOut,
    EditionCreate,
    EditionOut,
    EditionUpdate,
    GlobalSearchOut,
    PublisherCreate,
    PublisherOut,
    PublisherWorksOut,
    TranslationLinkIn,
    WorkCreate,
    WorkOut,
    WorkSummaryOut,
    WorkUpdate,
)
from app.services import catalog_service
from app.services.openlibrary_client import OpenLibraryClient, get_openlibrary_client

router = APIRouter(prefix="/catalog", tags=["catalog"])

OlClient = Annotated[OpenLibraryClient, Depends(get_openlibrary_client)]


def _summary(work) -> WorkSummaryOut:  # noqa: ANN001 — Work ORM instance
    edition = work.editions[0] if work.editions else None
    return WorkSummaryOut(
        id=work.id,
        title=work.title,
        first_publish_year=work.first_publish_year,
        aggregate_rating=work.aggregate_rating,
        authors=work.authors,
        edition=EditionOut.model_validate(edition) if edition else None,
    )


async def _work_out(db: AsyncSession, work) -> WorkOut:  # noqa: ANN001 — Work ORM instance
    rating = await catalog_service.translation_group_rating(db, work)
    siblings = await catalog_service.translation_siblings(db, work)
    return WorkOut.model_validate(work).model_copy(
        update={
            "translation_group_rating": rating,
            "translations": [_summary(w) for w in siblings],
        }
    )


@router.get("/search", response_model=list[WorkSummaryOut])
async def search(db: DbSession, q: str = Query(min_length=1)) -> list[WorkSummaryOut]:
    """Searches our own cached catalog (title / author / exact ISBN). Live
    OpenLibrary lookup is a separate call (GET /catalog/isbn/{isbn}) so a
    typo-laden free-text search doesn't burn an external request on every
    keystroke — the app calls that explicitly for the "add from ISBN" flow."""
    works = await catalog_service.search_local(db, q)
    return [_summary(w) for w in works]


@router.get("/search/all", response_model=GlobalSearchOut)
async def search_all(db: DbSession, q: str = Query(min_length=1)) -> GlobalSearchOut:
    """Global search (S4) — books, authors, and publishers for the app's search
    screen, in one request. The personal-library section is searched on-device
    (Drift), not here."""
    works = await catalog_service.search_local(db, q)
    authors = await catalog_service.search_authors(db, q)
    publishers = await catalog_service.search_publishers(db, q)
    return GlobalSearchOut(
        works=[_summary(w) for w in works],
        authors=[AuthorOut.model_validate(a) for a in authors],
        publishers=[PublisherOut.model_validate(p) for p in publishers],
    )


@router.get("/browse/works", response_model=list[WorkSummaryOut])
async def browse_works(
    db: DbSession,
    limit: int = Query(default=40, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    language: str | None = Query(default=None),
    sort: str = Query(default="title", pattern="^(title|year_desc|year_asc|author)$"),
) -> list[WorkSummaryOut]:
    """Discover screen — catalog books, paged, filterable by language and
    sortable by title / newest / oldest / author (S4/browse)."""
    works = await catalog_service.browse_works(db, limit, offset, language=language, sort=sort)
    return [_summary(w) for w in works]


@router.get("/browse/languages", response_model=list[str])
async def browse_languages(db: DbSession) -> list[str]:
    """Distinct catalog languages for the browse language filter."""
    return await catalog_service.catalog_languages(db)


@router.get("/browse/authors", response_model=list[AuthorOut])
async def browse_authors(
    db: DbSession,
    limit: int = Query(default=40, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name", pattern="^(name|popular)$"),
) -> list[AuthorOut]:
    """Discover screen (alphabetical) and the author picker's blank-state
    suggestions (`sort=popular` → most works first)."""
    authors = await catalog_service.browse_authors(db, limit, offset, popular=sort == "popular")
    return [AuthorOut.model_validate(a) for a in authors]


@router.get("/browse/publishers", response_model=list[PublisherOut])
async def browse_publishers(
    db: DbSession,
    limit: int = Query(default=40, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    sort: str = Query(default="name", pattern="^(name|popular)$"),
) -> list[PublisherOut]:
    """Discover screen (alphabetical) and the publisher picker's blank-state
    suggestions (`sort=popular` → most editions first)."""
    publishers = await catalog_service.browse_publishers(
        db, limit, offset, popular=sort == "popular"
    )
    return [PublisherOut.model_validate(p) for p in publishers]


@router.get("/isbn/{isbn}", response_model=WorkOut)
async def lookup_isbn(isbn: str, db: DbSession, ol_client: OlClient) -> WorkOut:
    """Scan flow (S7): local match first, else OpenLibrary — and whatever's
    found is cached locally so the next scan of this ISBN is instant."""
    edition = await catalog_service.find_or_fetch_by_isbn(db, ol_client, isbn)
    if edition is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "No book found for that ISBN"},
        )
    work = await catalog_service.get_work_or_404(db, edition.work_id)
    return await _work_out(db, work)


@router.post("/works", response_model=WorkOut, status_code=status.HTTP_201_CREATED)
async def create_work(payload: WorkCreate, user: CurrentUser, db: DbSession) -> WorkOut:
    """Manual add/edit flow (S7b). Credits the contributor for their score."""
    work = await catalog_service.create_work_with_edition(
        db, payload, created_by=uuid.UUID(user["id"])
    )
    return await _work_out(db, work)


@router.get("/works/{work_id}", response_model=WorkOut)
async def get_work(work_id: uuid.UUID, db: DbSession) -> WorkOut:
    work = await catalog_service.get_work_or_404(db, work_id)
    return await _work_out(db, work)


@router.patch("/works/{work_id}", response_model=WorkOut)
async def patch_work(
    work_id: uuid.UUID, payload: WorkUpdate, user: CurrentUser, db: DbSession
) -> WorkOut:
    work = await catalog_service.get_work_or_404(db, work_id)
    work = await catalog_service.update_work(db, work, payload)
    return await _work_out(db, work)


@router.post("/works/{work_id}/link-translation", status_code=status.HTTP_204_NO_CONTENT)
async def link_translation(
    work_id: uuid.UUID, payload: TranslationLinkIn, user: CurrentUser, db: DbSession
) -> None:
    """Link two Works as translations of one another (shared translation_group_id)
    — e.g. the Malayalam "Dantha Simhasanam" under the English "Ivory Throne"."""
    if work_id == payload.other_work_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "self_link", "message": "A Work can't be a translation of itself"},
        )
    work = await catalog_service.get_work_or_404(db, work_id)
    other = await catalog_service.get_work_or_404(db, payload.other_work_id)
    await catalog_service.link_translation(db, work, other)


@router.post(
    "/works/{work_id}/editions",
    response_model=EditionOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_edition(
    work_id: uuid.UUID, payload: EditionCreate, user: CurrentUser, db: DbSession
) -> EditionOut:
    """Add another edition (printing/ISBN) to an existing Work."""
    work = await catalog_service.get_work_or_404(db, work_id)
    edition = await catalog_service.create_edition(db, work, payload)
    return EditionOut.model_validate(edition)


@router.patch("/editions/{edition_id}", response_model=EditionOut)
async def patch_edition(
    edition_id: uuid.UUID, payload: EditionUpdate, user: CurrentUser, db: DbSession
) -> EditionOut:
    edition = await catalog_service.get_edition_or_404(db, edition_id)
    edition = await catalog_service.update_edition(db, edition, payload)
    return EditionOut.model_validate(edition)


@router.get("/authors", response_model=list[AuthorOut])
async def authors_typeahead(db: DbSession, q: str = Query(min_length=1)) -> list[AuthorOut]:
    """Add/edit form author field — suggests existing catalog authors so a
    user picks the canonical one instead of typing a near-duplicate."""
    return await catalog_service.search_authors(db, q)


@router.get("/publishers", response_model=list[PublisherOut])
async def publishers_typeahead(db: DbSession, q: str = Query(min_length=1)) -> list[PublisherOut]:
    """Add/edit form publisher field — same as authors_typeahead."""
    return await catalog_service.search_publishers(db, q)


@router.post("/authors", response_model=AuthorOut, status_code=status.HTTP_201_CREATED)
async def create_author(payload: AuthorCreate, user: CurrentUser, db: DbSession) -> AuthorOut:
    """Author picker "add new" — create a catalog author with details (image,
    primary language, bio). Get-or-create by name, so re-adding an existing
    author just returns the canonical one (only the first contributor is
    credited)."""
    author = await catalog_service.create_author(
        db, created_by_user_id=uuid.UUID(user["id"]), **payload.model_dump(exclude_none=True)
    )
    return AuthorOut.model_validate(author)


@router.post("/publishers", response_model=PublisherOut, status_code=status.HTTP_201_CREATED)
async def create_publisher(
    payload: PublisherCreate, user: CurrentUser, db: DbSession
) -> PublisherOut:
    """Publisher picker "add new" — same shape as create_author."""
    publisher = await catalog_service.create_publisher(db, **payload.model_dump(exclude_none=True))
    return PublisherOut.model_validate(publisher)


@router.get("/authors/{author_id}", response_model=AuthorWorksOut)
async def get_author(author_id: uuid.UUID, db: DbSession) -> AuthorWorksOut:
    """Author browse page (S4c) — every catalog work by this author."""
    author = await db.get(Author, author_id)
    if author is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Author not found"},
        )
    works = await catalog_service.author_works(db, author_id)
    return AuthorWorksOut(author=author, works=[_summary(w) for w in works])


@router.get("/publishers/{publisher_id}", response_model=PublisherWorksOut)
async def get_publisher(publisher_id: uuid.UUID, db: DbSession) -> PublisherWorksOut:
    """Publisher browse page (S4d) — every catalog work from this publisher."""
    publisher = await db.get(Publisher, publisher_id)
    if publisher is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Publisher not found"},
        )
    works = await catalog_service.publisher_works(db, publisher_id)
    return PublisherWorksOut(publisher=publisher, works=[_summary(w) for w in works])
