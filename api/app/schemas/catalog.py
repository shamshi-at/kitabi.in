import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class AuthorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    pen_name: str | None = None
    image_url: str | None = None
    primary_language: str | None = None


class AuthorDetailOut(AuthorOut):
    """Author with the fuller fields the browse/share pages show (bio) — the
    typeahead-lean AuthorOut stays small for suggestion lists."""

    bio: str | None = None


class PublisherOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    logo_url: str | None = None
    primary_language: str | None = None


class AuthorCreate(BaseModel):
    """Create a catalog author with details from the author picker's "add new"
    flow. Get-or-create by name server-side, so this is idempotent on name."""

    name: str
    pen_name: str | None = None
    image_url: str | None = None
    primary_language: str | None = None
    bio: str | None = None


class PublisherCreate(BaseModel):
    name: str
    logo_url: str | None = None
    primary_language: str | None = None


class GenreOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str


class SeriesOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str


class EditionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    isbn: str | None
    language: str | None
    page_count: int | None
    pub_date: date | None
    format: str | None
    cover_url: str | None
    # [WIRED] external buy link — null until store links are populated; the app
    # only shows a "Buy" affordance when it's set.
    buy_url: str | None = None
    series_number: int | None
    publisher: PublisherOut | None
    series: SeriesOut | None


class WorkOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    title: str
    subtitle: str | None
    description: str | None
    language: str | None
    first_publish_year: int | None
    aggregate_rating: float | None
    translation_group_id: uuid.UUID | None
    # Display-only aggregate across every Work sharing translation_group_id —
    # this Work's own aggregate_rating stays independent (product decision,
    # 5 Jul 2026: each translation keeps its own rating pool).
    translation_group_rating: float | None = None
    authors: list[AuthorOut]
    genres: list[GenreOut]
    editions: list[EditionOut]
    created_at: datetime


class WorkSummaryOut(BaseModel):
    """A lighter Work shape for browse/search lists — one representative
    edition instead of the full list, so list endpoints don't ship every
    printing of every book."""

    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    title: str
    first_publish_year: int | None
    aggregate_rating: float | None
    authors: list[AuthorOut]
    edition: EditionOut | None


class WorkCreate(BaseModel):
    title: str
    subtitle: str | None = None
    description: str | None = None
    language: str | None = None
    first_publish_year: int | None = None
    # Authors/publisher can be referenced either by their catalog id (the app's
    # author/publisher pickers yield canonical ids) or by name (free-text /
    # OpenLibrary import). Ids win; names get the case-insensitive
    # get-or-create. Both are optional so either path works.
    author_ids: list[uuid.UUID] = []
    author_names: list[str] = []
    genre_names: list[str] = []
    publisher_id: uuid.UUID | None = None
    publisher_name: str | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: str | None = None
    page_count: int | None = None
    pub_date: date | None = None
    format: str | None = None
    cover_url: str | None = None


class WorkUpdate(BaseModel):
    title: str | None = None
    subtitle: str | None = None
    description: str | None = None
    language: str | None = None
    first_publish_year: int | None = None
    author_ids: list[uuid.UUID] | None = None
    author_names: list[str] | None = None
    genre_names: list[str] | None = None


class EditionUpdate(BaseModel):
    publisher_id: uuid.UUID | None = None
    publisher_name: str | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: str | None = None
    page_count: int | None = None
    pub_date: date | None = None
    format: str | None = None
    cover_url: str | None = None
    buy_url: str | None = None


class TranslationLinkIn(BaseModel):
    other_work_id: uuid.UUID


class RecommendationOut(BaseModel):
    work: WorkSummaryOut
    why: str


class RecommendationsOut(BaseModel):
    """`enabled` is False when no LLM key is configured — the app shows the
    opt-in/off state accordingly (feature-map.md: always-visible off switch)."""

    enabled: bool
    picks: list[RecommendationOut]


class ImportPreviewIn(BaseModel):
    csv: str


class ImportRowOut(BaseModel):
    title: str
    author: str | None = None
    isbn: str | None = None
    rating: int | None = None
    review: str | None = None
    status: str | None = None
    date_read: str | None = None
    tags: list[str] = []
    # The catalog work this row matched, if any — the app adds this edition to
    # the library on confirm; unmatched rows can be resolved by ISBN then.
    match: WorkSummaryOut | None = None


class ImportPreviewOut(BaseModel):
    format: str  # 'goodreads' | 'generic'
    total: int
    matched: int
    rows: list[ImportRowOut]


class AuthorWorksOut(BaseModel):
    author: AuthorDetailOut
    works: list[WorkSummaryOut]


class PublisherWorksOut(BaseModel):
    publisher: PublisherOut
    works: list[WorkSummaryOut]


class GlobalSearchOut(BaseModel):
    """One call behind the app's global search — books, authors, and publishers
    in a single round-trip so the search screen can show all three sections
    without three separate requests."""

    works: list[WorkSummaryOut]
    authors: list[AuthorOut]
    publishers: list[PublisherOut]
