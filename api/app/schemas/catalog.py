"""Pydantic request/response schemas for the catalog: works, editions, authors,
publishers, ISBN lookup, CSV import rows, and recommendations."""

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, field_validator


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


class BuyLink(BaseModel):
    """One external retailer link for an edition ([WIRED] — the book page lists
    every store the book is available at)."""

    model_config = ConfigDict(from_attributes=True)
    retailer: str
    url: str


class EditionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    isbn: str | None
    language: str | None
    page_count: int | None
    pub_date: date | None
    format: str | None
    cover_url: str | None
    back_cover_url: str | None
    # [WIRED] where to buy — empty until store links are populated; the book
    # page lists each retailer.
    buy_links: list[BuyLink] = []
    series_number: int | None
    publisher: PublisherOut | None
    series: SeriesOut | None

    @field_validator("buy_links", mode="before")
    @classmethod
    def _null_buy_links_to_empty(cls, v: object) -> object:
        # The column is nullable; render null as an empty list.
        return v if v is not None else []


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
    # Other Works sharing this one's translation_group_id — e.g. the Malayalam
    # "Dantha Simhasanam" listed on the English "Ivory Throne" and vice versa.
    # Computed at read time (a translation is its own Work, only group-linked).
    translations: list["WorkSummaryOut"] = []
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


# WorkOut.translations forward-references WorkSummaryOut (defined just above) —
# resolve it now that both classes exist.
WorkOut.model_rebuild()


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
    back_cover_url: str | None = None


class WorkUpdate(BaseModel):
    title: str | None = None
    subtitle: str | None = None
    description: str | None = None
    language: str | None = None
    first_publish_year: int | None = None
    author_ids: list[uuid.UUID] | None = None
    author_names: list[str] | None = None
    genre_names: list[str] | None = None


class WorkPatchResult(BaseModel):
    """PATCH /works outcome. `applied` False means the edit was queued as a
    pending revision for the Work's contributor to approve (wiki-style
    moderation) — `work` is then the still-unchanged live entry."""

    applied: bool
    revision_id: uuid.UUID | None = None
    work: "WorkOut"


class WorkRevisionOut(BaseModel):
    """One pending edit in the contributor's approval inbox."""

    id: uuid.UUID
    work_id: uuid.UUID
    work_title: str
    proposed_by_name: str | None = None
    payload: dict
    status: str
    created_at: datetime


class EditionCreate(BaseModel):
    """Add another printing/ISBN to an existing Work — the edition-level library
    (a paperback of a book you own in hardcover, a regional reprint, …)."""

    publisher_id: uuid.UUID | None = None
    publisher_name: str | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: str | None = None
    language: str | None = None
    page_count: int | None = None
    pub_date: date | None = None
    format: str | None = None
    cover_url: str | None = None
    back_cover_url: str | None = None


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
    back_cover_url: str | None = None
    buy_links: list[BuyLink] | None = None


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


class CoverExtractIn(BaseModel):
    """Cover photo URL(s) already uploaded to the public covers bucket by the
    add-book form. At least one side must be given (validated in the router,
    which also restricts the URLs to our own bucket)."""

    front_url: str | None = None
    back_url: str | None = None


class CoverExtractOut(BaseModel):
    """What the vision model could read off the photographs — every field
    optional; the form prefills only what it received and only into empty
    fields. Never persisted server-side."""

    title: str | None = None
    authors: list[str] = []
    publisher: str | None = None
    description: str | None = None
    series_name: str | None = None
    series_number: int | None = None
    language: str | None = None
    isbn: str | None = None


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


class PublicReviewerOut(BaseModel):
    """Who wrote a public review. `is_public` tells the client whether `id`
    is safe to open as a profile — when false, `display_name` is an
    anonymous placeholder and `avatar_url` is always null."""

    id: uuid.UUID
    display_name: str
    avatar_url: str | None
    is_public: bool


class PublicReviewOut(BaseModel):
    """One reader's public review of a Work, with their star rating for the
    same book attached if they left one (a rating with no public review
    stays out of this list entirely — feature-map.md defers public ratings)."""

    id: uuid.UUID
    body: str
    rating: int | None
    created_at: datetime
    reviewer: PublicReviewerOut


class PublicReviewsPageOut(BaseModel):
    """Everything the book page's reviews section needs in one call: the
    visible reviews (newest first — the app sorts/paginates client-side over
    this list, so there's no server-side sort/offset param to keep in sync)
    plus the community rating picture computed from every rating on the
    work, not just the ones attached to a public review."""

    reviews: list[PublicReviewOut]
    rating_average: float | None
    rating_count: int
    rating_distribution: dict[int, int]
