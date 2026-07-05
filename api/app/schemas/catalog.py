import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class AuthorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    pen_name: str | None = None
    image_url: str | None = None


class PublisherOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    logo_url: str | None = None


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
    author_names: list[str] = []
    genre_names: list[str] = []
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
    author_names: list[str] | None = None
    genre_names: list[str] | None = None


class EditionUpdate(BaseModel):
    publisher_name: str | None = None
    series_name: str | None = None
    series_number: int | None = None
    isbn: str | None = None
    page_count: int | None = None
    pub_date: date | None = None
    format: str | None = None
    cover_url: str | None = None


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


class AuthorWorksOut(BaseModel):
    author: AuthorOut
    works: list[WorkSummaryOut]


class PublisherWorksOut(BaseModel):
    publisher: PublisherOut
    works: list[WorkSummaryOut]
