"""Pydantic request/response schemas for the catalog: works, editions, authors,
publishers, ISBN lookup, CSV import rows, and recommendations."""

import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, field_validator

from app.services import isbn as isbn_util

# Every ISBN entering the API, canonicalised to ISBN-13 where that can be
# derived. Applied as a type rather than a per-model validator so a new schema
# with an ISBN field cannot quietly skip it — the catalogue converging on one
# form is what lets a lookup be an index hit rather than a set of guesses.
# Unrecognisable input passes through untouched (see normalize_for_storage).
NormalizedIsbn = Annotated[str | None, BeforeValidator(isbn_util.normalize_for_storage)]

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
    # തിരക്കഥ is a shelf of its own in Malayalam publishing — the screenplay of
    # a novel is sold as its own book, and readers own both (owner report,
    # 13 Aug 2026). Also teaches the cover-extract prompt to recognise it.
    "Screenplay",
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


# The physical shape of a printing — Edition.format, which the app calls
# "Format" and offers as four chips. Separate axis from WORK_FORMS (the
# *literary* form): a screenplay can be a paperback.
EDITION_FORMATS = ("Paperback", "Hardcover", "eBook", "Audiobook")

# What the world actually writes for those four. OpenLibrary's
# `physical_format` is free text filled in by thousands of contributors, so it
# arrives as "pbk.", "Trade Paperback", "hardback", "Electronic resource" — one
# printing's shape spelled a dozen ways. Substring matching, because the useful
# word is nearly always in there somewhere ("Mass Market Paperback").
_FORMAT_HINTS = (
    ("Hardcover", ("hardcover", "hardback", "hard cover", "hbk", "casebound", "boards")),
    ("Paperback", ("paperback", "paper back", "pbk", "softcover", "soft cover", "trade pb")),
    ("eBook", ("ebook", "e-book", "electronic", "kindle", "epub", "pdf", "digital")),
    ("Audiobook", ("audiobook", "audio book", "audio cd", "audio", "mp3", "spoken", "cassette")),
)


def normalize_edition_format(value: str | None) -> str | None:
    """Fold a printing's format onto one of [EDITION_FORMATS], or keep it.

    Same bargain as [normalize_form]: the vocabulary is suggested, not closed,
    so a format we did not think of survives rather than being thrown away — but
    the spellings we *can* recognise are folded, or the facet splits four ways
    and the app's chip row silently fails to preselect anything.
    """
    if value is None:
        return None
    cleaned = " ".join(value.split())
    if not cleaned:
        return None
    for known in EDITION_FORMATS:
        if cleaned.casefold() == known.casefold():
            return known
    lowered = cleaned.casefold()
    for known, hints in _FORMAT_HINTS:
        if any(hint in lowered for hint in hints):
            return known
    return cleaned


# Applied as a type, for the reason NormalizedIsbn is: a new schema carrying a
# format cannot quietly skip the folding.
NormalizedFormat = Annotated[str | None, BeforeValidator(normalize_edition_format)]


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
    # True only for the reader who filed an unresolved "This is me" claim on
    # this author. Deliberately per-request and private: it is the *only* trace
    # of a pending claim anyone sees, and everyone else must keep seeing the
    # old `linked_user_id`. Never set from the ORM row — see
    # catalog.py's `_with_claims`.
    claim_pending: bool = False


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
    # "This is me" — the add-author form's checkbox. Files a claim for review;
    # it does not link the row (app/models/author_claim.py).
    is_me: bool = False


class PublisherCreate(BaseModel):
    name: str
    logo_url: str | None = None
    primary_language: str | None = None


class GenreOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str


class GenreCountOut(BaseModel):
    """A genre in the catalogue and how many works carry it — the shape the
    add form's genre picker needs. The count is what makes an existing genre
    the obvious pick over a new near-duplicate spelling (mockup M11)."""

    name: str
    work_count: int


class SeriesOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    slug: str | None = None
    name_translit: str | None = None
    primary_language: str | None = None
    description: str | None = None


class SeriesWithCountOut(SeriesOut):
    """A series and how many books it holds — the browse list and the picker.
    The count is what separates a real series from the empty row a typo left
    behind, so it travels with the name everywhere a series is chosen."""

    book_count: int = 0


class SeriesCreate(BaseModel):
    name: str
    primary_language: str | None = None
    description: str | None = None


class BuyLink(BaseModel):
    """One external retailer link for an edition — the stored, contributor-
    entered shape (the `buy_links` JSONB on Edition). Write paths use exactly
    this, so nothing computed ever lands in the column."""

    model_config = ConfigDict(from_attributes=True)
    retailer: str
    url: str


class BuyLinkOut(BuyLink):
    """What the API *serves*: stored links plus the affiliate links generated
    from the ISBN at read time (`services/buy_links.py`). `affiliate` is True
    only for a link that pays Kitabi — clients show a disclosure beside those,
    and the web renderer marks them rel="sponsored"."""

    affiliate: bool = False


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
    # Where to buy — the stored links merged with the generated affiliate
    # links (services/buy_links.py) by the work serializers; the book page
    # lists each retailer.
    buy_links: list[BuyLinkOut] = []
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
    # Where this book sits in a series, if it does. On the Work since migration
    # 000043; EditionOut carries the same values for app installs that still
    # read them there.
    series: SeriesOut | None = None
    series_number: int | None = None
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
    # Which of those editions the caller actually asked for. Set only by
    # `GET /catalog/isbn/{isbn}`, which knows precisely which printing carries
    # the barcode that was scanned — the rest of the response is the whole
    # Work, and picking `editions[0]` out of it shelved the wrong printing
    # (owner report, 13 Aug 2026: scanning a 240-page reprint put the 55-page
    # first edition on the shelf). Null everywhere else.
    scanned_edition_id: uuid.UUID | None = None
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
    # So a browse row can say "Book 2 of Malgudi" without a detail fetch.
    series: SeriesOut | None = None
    series_number: int | None = None
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
    # Picked series wins over typed; both land on the Work (migration 000043).
    series_id: uuid.UUID | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: NormalizedIsbn = None
    page_count: int | None = None
    pub_date: date | None = None
    format: NormalizedFormat = None
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
    # Series membership is a property of the Work (migration 000043). `_id` is
    # what every picker sends; `_name` stays for the import/extraction paths
    # that only ever have a string.
    series_id: uuid.UUID | None = None
    series_name: str | None = None
    series_number: int | None = None

    _check_form = field_validator("form")(_validate_form)


class WorkPatchResult(BaseModel):
    """PATCH /works outcome. `applied` False means the edit was queued as a
    pending revision for the Work's contributor to approve (wiki-style
    moderation) — `work` is then the still-unchanged live entry."""

    applied: bool
    revision_id: uuid.UUID | None = None
    work: "WorkOut"


class WorkMergeRequest(BaseModel):
    """ "These are all the same book" — fold `absorb_ids` into one survivor.

    A list rather than a pair because that is the shape of the problem: a
    typo'd title arrives as three or four rows at once, and merging them one at
    a time means re-picking the survivor at every step.
    """

    # Capped because this is a reader-facing write that soft-deletes catalogue
    # rows; nobody legitimately folds a dozen books together in one gesture.
    absorb_ids: list[uuid.UUID] = Field(min_length=1, max_length=10)


class WorkMergeResult(BaseModel):
    """What the merge actually did. `merged` names the rows that went away, so
    the app can say so rather than leaving the reader to infer it."""

    work: "WorkOut"
    merged: list["MergedWorkOut"]


class MergedWorkOut(BaseModel):
    id: uuid.UUID
    title: str


class WorkRevisionOut(BaseModel):
    """One pending edit in the contributor's approval inbox."""

    id: uuid.UUID
    work_id: uuid.UUID
    work_title: str
    proposed_by_name: str | None = None
    payload: dict
    status: str
    created_at: datetime


class AuthorClaimOut(BaseModel):
    """One of the reader's own "This is me" claims, for the screen that lets
    them see it is pending and take it back."""

    id: uuid.UUID
    author_id: uuid.UUID
    author_name: str
    status: str
    created_at: datetime


class EditionCreate(BaseModel):
    """Add another printing/ISBN to an existing Work — the edition-level library
    (a paperback of a book you own in hardcover, a regional reprint, …).

    The three Work-level fields at the bottom are not edition data and are
    never written onto the Edition. They exist because the reader adding a
    printing is standing there with the book, often in front of a Work that is
    a bare stub: whatever the back cover says goes to fill the *Work's* empty
    blurb, type and year (owner request, 13 Aug 2026). An answer the Work
    already has is never overwritten.
    """

    publisher_id: uuid.UUID | None = None
    publisher_name: str | None = None
    # Accepted here for app installs that predate the move to the Work; the
    # service redirects it there rather than writing the edition's own column.
    series_id: uuid.UUID | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: NormalizedIsbn = None
    language: str | None = None
    page_count: int | None = None
    pub_date: date | None = None
    format: NormalizedFormat = None
    cover_url: str | None = None
    back_cover_url: str | None = None
    # Work-level, fill-if-empty — see the class docstring.
    description: str | None = None
    form: str | None = None
    first_publish_year: int | None = None

    _check_form = field_validator("form")(_validate_form)


class EditionUpdate(BaseModel):
    publisher_id: uuid.UUID | None = None
    publisher_name: str | None = None
    # Picked series wins over typed; both land on the Work (migration 000043).
    series_id: uuid.UUID | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: NormalizedIsbn = None
    page_count: int | None = None
    pub_date: date | None = None
    format: NormalizedFormat = None
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
    # Which half of the read to run. The identity fields come back in a second
    # or two; the back-cover blurb is up to 150 words and, in Malayalam, most
    # of the wait — so the form asks for them separately and fills the blurb in
    # behind the title. Omitted runs both concurrently and merges, which is
    # what an app build older than the split sends (and what a caller that
    # simply wants everything in one response gets).
    part: Literal["identity", "description"] | None = None


class CoverExtractOut(BaseModel):
    """What the vision model could read off the photographs — every field
    optional; the form prefills only what it received and only into empty
    fields. Never persisted server-side."""

    title: str | None = None
    authors: list[str] = []
    publisher: str | None = None
    # The catalogue row the read name resolves to, when the catalogue already
    # has that house. Sent so the form can show — and save against — the
    # publisher every other book sits on, instead of the spelling this one
    # cover happens to print. Null when it would be a genuinely new house, and
    # then `publisher` is the read name verbatim.
    publisher_id: uuid.UUID | None = None
    description: str | None = None
    series_name: str | None = None
    series_number: int | None = None
    language: str | None = None
    # The literary form ("Type"), read off the back cover when it names one
    # (e.g. a Malayalam നോവൽ → "Novel"); one of WORK_FORMS or None. The service
    # already computes this — surfacing it here lets the form prefill the Type.
    form: str | None = None
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


class ReviewReportIn(BaseModel):
    """A reader reporting someone else's public review. The reason is a short
    free string, not an enum — the app sends one of its fixed labels today, but
    the queue must not reject a client that learns a new word before the server
    does (the same open-vocabulary rule as WORK_FORMS)."""

    reason: str | None = None

    @field_validator("reason")
    @classmethod
    def _trim_reason(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if len(v) > 200:
            raise ValueError("reason must be 200 characters or fewer")
        return v or None


class ReviewReportOut(BaseModel):
    """What became of the report: `filed`, or the quiet idempotent outcomes
    `already_reported` / `already_hidden` — all of which the app renders as
    the same thank-you."""

    status: str
