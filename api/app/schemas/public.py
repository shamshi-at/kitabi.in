"""Response shapes for the public web site (kitabi.in).

Deliberately **page-shaped, not resource-shaped**. The rest of the catalog API
is REST-ish because the mobile app is offline-first and wants entities it can
cache and sync; the public web renders once at the edge and wants whole pages.
Four sequential edge→Singapore round trips to assemble one book page is ~1.2 s
of TTFB before a byte is rendered, so each endpoint here returns everything one
page needs in a single call (docs/web-platform-plan.md §3).

Everything is a thin projection over the same services the app uses — no
duplicated business logic, and nothing here is writable.
"""

from __future__ import annotations

import uuid
from datetime import date

from pydantic import BaseModel

from app.schemas.catalog import BuyLink, PublicReviewOut


class Ref(BaseModel):
    """A linkable catalog entity reduced to what a hyperlink needs. `slug` is
    nullable — a row whose title romanizes to nothing has none, and the site
    falls back to its id (slug_service)."""

    id: uuid.UUID
    name: str
    slug: str | None = None
    image_url: str | None = None


class WorkCard(BaseModel):
    """The atom every grid, strip and search result on the site is built from.

    One shape for all of them on purpose: the mockups' "covers first, one frame
    for all" rule is a rendering promise that only holds if every list is fed
    identical data (docs/screen-design.md).
    """

    id: uuid.UUID
    slug: str | None = None
    title: str
    year: int | None = None
    language: str | None = None
    form: str | None = None
    rating: float | None = None
    rating_count: int = 0
    cover_url: str | None = None
    authors: list[Ref] = []
    # Set only inside a translation group, so a card can be badged "Original"
    # without a second fetch.
    is_original: bool | None = None


class RatingSummary(BaseModel):
    average: float | None = None
    count: int = 0
    # {"5": 193, "4": 81, …} — the histogram on the book page.
    distribution: dict[str, int] = {}


class PublicEdition(BaseModel):
    id: uuid.UUID
    isbn: str | None = None
    language: str | None = None
    page_count: int | None = None
    pub_date: date | None = None
    year: int | None = None
    format: str | None = None
    cover_url: str | None = None
    back_cover_url: str | None = None
    series_number: int | None = None
    publisher: Ref | None = None
    series: Ref | None = None
    buy_links: list[BuyLink] = []


class BookPage(BaseModel):
    """Everything `/book/<slug>` renders, in one call."""

    id: uuid.UUID
    slug: str | None = None
    title: str
    subtitle: str | None = None
    description: str | None = None
    language: str | None = None
    form: str | None = None
    first_publish_year: int | None = None

    authors: list[Ref] = []
    translators: list[Ref] = []
    genres: list[Ref] = []
    editions: list[PublicEdition] = []

    # The translation graph — the one thing no competitor can show, so it gets
    # its own block rather than being flattened into "related".
    translations: list[WorkCard] = []
    original: WorkCard | None = None
    translation_group_rating: float | None = None

    rating: RatingSummary = RatingSummary()
    reviews: list[PublicReviewOut] = []

    more_by_author: list[WorkCard] = []
    related: list[WorkCard] = []

    # Whether this page clears the content floor and may be indexed
    # (docs/web-platform-plan.md §8.3). The renderer emits the robots tag from
    # this, and the sitemap filters on the same rule.
    indexable: bool = True


class AuthorPage(BaseModel):
    id: uuid.UUID
    slug: str | None = None
    name: str
    pen_name: str | None = None
    bio: str | None = None
    image_url: str | None = None
    primary_language: str | None = None
    # True when this author is a verified reader here — a genuinely novel
    # signal, so the page says so.
    on_kitabi: bool = False

    works: list[WorkCard] = []
    translated_works: list[WorkCard] = []
    publishers: list[Ref] = []
    languages: list[str] = []
    work_count: int = 0
    edition_count: int = 0
    rating: float | None = None
    # first_publish_year → count, for the small timeline on the page.
    decades: dict[str, int] = {}
    indexable: bool = True


class PublisherPage(BaseModel):
    id: uuid.UUID
    slug: str | None = None
    name: str
    logo_url: str | None = None
    primary_language: str | None = None
    works: list[WorkCard] = []
    total: int = 0
    authors: list[Ref] = []
    languages: list[str] = []
    edition_count: int = 0
    earliest_year: int | None = None
    decades: dict[str, int] = {}
    indexable: bool = True


class SeriesPage(BaseModel):
    id: uuid.UUID
    slug: str | None = None
    name: str
    works: list[WorkCard] = []
    indexable: bool = True


class TranslationGroupPage(BaseModel):
    """One book across every language it exists in — the page that should win
    "<title> English translation"."""

    group_id: uuid.UUID
    title: str
    original: WorkCard | None = None
    translations: list[WorkCard] = []
    translators: list[Ref] = []
    group_rating: float | None = None
    group_rating_count: int = 0
    description: str | None = None


class LanguageCount(BaseModel):
    name: str
    slug: str
    count: int


class GenreCount(BaseModel):
    name: str
    slug: str
    count: int


class TranslationPair(BaseModel):
    original: WorkCard
    translation: WorkCard


class HomePage(BaseModel):
    featured: WorkCard | None = None
    recent: list[WorkCard] = []
    top_rated: list[WorkCard] = []
    languages: list[LanguageCount] = []
    genres: list[GenreCount] = []
    translation_pairs: list[TranslationPair] = []
    work_count: int = 0
    author_count: int = 0
    publisher_count: int = 0


class HubPage(BaseModel):
    """Genre, language, and language+form hubs share one shape — they are the
    same page with a different filter, and the mockups draw them as one
    template."""

    kind: str  # "genre" | "language" | "form"
    name: str
    slug: str
    form: str | None = None
    works: list[WorkCard] = []
    start_here: list[WorkCard] = []
    total: int = 0
    page: int = 1
    per_page: int = 24
    languages: list[LanguageCount] = []
    forms: list[GenreCount] = []
    genres: list[GenreCount] = []
    authors: list[Ref] = []
    translated_count: int = 0
    author_count: int = 0
    publisher_count: int = 0
    earliest_year: int | None = None


class SearchPage(BaseModel):
    q: str
    works: list[WorkCard] = []
    authors: list[Ref] = []
    publishers: list[Ref] = []
    total: int = 0
    # The cross-script party trick, made visible: "also matched ചെമ്മീൻ".
    matched_scripts: list[str] = []


class BrowsePage(BaseModel):
    works: list[WorkCard] = []
    total: int = 0
    page: int = 1
    per_page: int = 24
    languages: list[LanguageCount] = []
    forms: list[GenreCount] = []
    genres: list[GenreCount] = []
