"""Pydantic request/response schemas for the catalog: works, editions, authors,
publishers, ISBN lookup, CSV import rows, and recommendations."""

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator

# The suggested vocabulary for Work.form — the literary form (the app calls it
# "Type"): one per work, a separate axis from genre (owner decision, 16 Jul
# 2026). These are the chips the add form offers and the order it offers them
# in; the cover-extract prompt draws from the same list.
#
# Suggested, not closed (owner request, 16 Jul 2026): a reader whose book is a
# form we didn't think of — a novella, a screenplay, a devotional — must be
# able to say so rather than leave it blank. Free values are normalised below
# instead of rejected, which is what actually keeps the catalog clean.
WORK_FORMS = (
    "Novel",
    "Short stories",
    "Poetry",
    "Memoir",
    "Biography",
    "Essays",
    "Play",
    "Travelogue",
    "Children's",
    "Graphic novel",
)

MAX_FORM_LEN = 40


def normalize_form(value: str | None) -> str | None:
    """Fold a form onto its canonical spelling. A custom value is kept, but
    case-insensitively matched against the vocabulary first, so "novel" and
    "NOVEL" become "Novel" rather than splitting the facet three ways — the
    near-duplicate problem a closed list was there to prevent, solved without
    turning a reader's honest answer away."""
    if value is None:
        return None
    cleaned = " ".join(value.split())  # collapse stray whitespace
    if not cleaned:
        return None
    for known in WORK_FORMS:
        if cleaned.casefold() == known.casefold():
            return known
    return cleaned


def _validate_form(value: str | None) -> str | None:
    cleaned = normalize_form(value)
    if cleaned is not None and len(cleaned) > MAX_FORM_LEN:
        raise ValueError(f"form must be at most {MAX_FORM_LEN} characters")
    return cleaned


class AuthorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    pen_name: str | None = None
    image_url: str | None = None
    primary_language: str | None = None
    # The Profile who is this author, if self-linked — drives the 🔗 "on
    # Kitabi" badge and the "View their Kitabi profile" door.
    linked_user_id: uuid.UUID | None = None


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
    # "This is me" — the add-author form's checkbox, shown only when creating
    # a brand-new author. Self-links the new row to the signed-in reader.
    is_me: bool = False


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
    # The literary form ("Type" in the UI) — one of WORK_FORMS, or null.
    form: str | None = None
    aggregate_rating: float | None
    translation_group_id: uuid.UUID | None
    # Which Work this one was translated *from* — the direction on top of the
    # undirected group. Null on originals and legacy flat-linked groups.
    original_work_id: uuid.UUID | None = None
    # Display-only aggregate across every Work sharing translation_group_id —
    # this Work's own aggregate_rating stays independent (product decision,
    # 5 Jul 2026: each translation keeps its own rating pool).
    translation_group_rating: float | None = None
    authors: list[AuthorOut]
    # Who translated this Work — Author rows too (same catalog pages), joined
    # via work_translators. Empty on originals.
    translators: list[AuthorOut] = []
    genres: list[GenreOut]
    editions: list[EditionOut]
    # Other Works sharing this one's translation_group_id — e.g. the Malayalam
    # "Dantha Simhasanam" listed on the English "Ivory Throne" and vice versa.
    # Computed at read time (a translation is its own Work, only group-linked).
    translations: list["WorkSummaryOut"] = []
    # The original Work's summary when original_work_id is set — computed at
    # read time for the book page's "Translation of …" card.
    original: "WorkSummaryOut | None" = None
    created_at: datetime


class WorkSummaryOut(BaseModel):
    """A lighter Work shape for browse/search lists — one representative
    edition instead of the full list, so list endpoints don't ship every
    printing of every book."""

    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    title: str
    first_publish_year: int | None
    form: str | None = None
    aggregate_rating: float | None
    # Group membership + direction, so pickers/lists can badge "Original" and
    # "in group" without a detail fetch (T2's stamps).
    translation_group_id: uuid.UUID | None = None
    original_work_id: uuid.UUID | None = None
    authors: list[AuthorOut]
    translators: list[AuthorOut] = []
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
    form: str | None = None
    # Authors/publisher can be referenced either by their catalog id (the app's
    # author/publisher pickers yield canonical ids) or by name (free-text /
    # OpenLibrary import). Ids win; names get the case-insensitive
    # get-or-create. Both are optional so either path works.
    author_ids: list[uuid.UUID] = []
    author_names: list[str] = []
    # Translator credits — same id-or-name resolution as authors (the form's
    # Translator field reuses the author picker). Only meaningful alongside
    # original_work_id, but not enforced: a translation whose original isn't
    # linked yet may still credit its translator.
    translator_ids: list[uuid.UUID] = []
    translator_names: list[str] = []
    # "Translated from" — link this new Work to its original at create time
    # (T1/T4). Joins/creates the original's translation group and records the
    # direction. Silently ignored if the id doesn't resolve.
    original_work_id: uuid.UUID | None = None
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

    _check_form = field_validator("form")(_validate_form)


class WorkUpdate(BaseModel):
    title: str | None = None
    subtitle: str | None = None
    description: str | None = None
    language: str | None = None
    first_publish_year: int | None = None
    form: str | None = None
    author_ids: list[uuid.UUID] | None = None
    author_names: list[str] | None = None
    translator_ids: list[uuid.UUID] | None = None
    translator_names: list[str] | None = None
    genre_names: list[str] | None = None

    _check_form = field_validator("form")(_validate_form)


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
    # How the other Work relates to the one in the URL:
    #   "original"    — the other Work is this one's original (T1's post-hoc link)
    #   "translation" — the other Work is a translation of this one (T6's link)
    #   "sibling"     — direction unknown; group-link only (legacy behavior)
    relation: Literal["sibling", "original", "translation"] = "sibling"


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
