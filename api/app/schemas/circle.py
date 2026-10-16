"""Pydantic shapes for "your circle" — what a reader's accepted connections who
chose to share have read, rated and own (docs/circle-reading-mockups.html)."""

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.catalog import WorkSummaryOut

# A search page is at most this many rows; the batch endpoint refuses more so a
# client bug can't turn one request into a scan of the whole catalogue.
MAX_SIGNAL_WORKS = 50


class CirclePersonOut(BaseModel):
    """One connection, as far as they've agreed to be seen on one book."""

    user_id: uuid.UUID
    name: str
    avatar_url: str | None = None
    # 'read' | 'reading' | None (None = only shown because they own a copy).
    status: Literal["read", "reading"] | None = None
    # Finished passes (rule 19 — derived from `reads`, never stored); 0 unless read.
    read_count: int = 0
    finished_on: date | None = None
    started_on: date | None = None
    # Present only when they share ratings (which ride on sharing reading).
    rating: int | None = None
    # Only a review they made public — this endpoint can't widen a review's audience.
    review: str | None = None
    owns: bool = False
    owned_edition_id: uuid.UUID | None = None
    owned_edition_label: str | None = None
    # The caller has an open ask with this owner for this book.
    asked: bool = False


class CircleSignalOut(BaseModel):
    """The one-line summary a search row needs: counts plus up to three faces
    per bucket, newest first."""

    read_count: int = 0
    reading_count: int = 0
    owns_count: int = 0
    readers: list[CirclePersonOut] = []
    reading: list[CirclePersonOut] = []
    owners: list[CirclePersonOut] = []
    avg_rating: float | None = None
    # False when the caller already has this book on a shelf (any but
    # Wishlist) — no "ask to borrow" for a book you hold or have read.
    can_ask: bool = True


class CircleSignalsIn(BaseModel):
    work_ids: list[uuid.UUID] = Field(min_length=1, max_length=MAX_SIGNAL_WORKS)


class CircleSignalsOut(BaseModel):
    """`invite` is set instead of signals when the caller shares nothing: the
    number of their connections who do (their consent, theirs to reveal). Zero
    means there is nothing to show at all."""

    invite: int | None = None
    signals: dict[str, CircleSignalOut] = {}


class CircleTranslationOut(BaseModel):
    """The same book in another language, read by someone in the circle."""

    work_id: uuid.UUID
    # Any printing of it — the app's book route is addressed by work + edition.
    edition_id: uuid.UUID | None = None
    title: str
    language: str | None = None
    read_count: int
    names: list[str]


class CircleWorkOut(BaseModel):
    invite: int | None = None
    people: list[CirclePersonOut] = []
    read_count: int = 0
    reading_count: int = 0
    owns_count: int = 0
    avg_rating: float | None = None
    translations: list[CircleTranslationOut] = []
    can_ask: bool = True


PickKind = Literal["borrow", "read_along", "loved", "cluster", "kindred"]


class CirclePickOut(BaseModel):
    """Home's one "From your circle" card. `kind` picks the sentence; `person`
    is the friend it names (absent for a cluster, which names `people`)."""

    kind: PickKind
    work: WorkSummaryOut
    person: CirclePersonOut | None = None
    people: list[CirclePersonOut] = []
    # Others in the circle who read the same book (the card's "also read by").
    also_read_count: int = 0
    # The reader's own rating, for "kindred".
    my_rating: int | None = None


class CirclePickResponse(BaseModel):
    invite: int | None = None
    pick: CirclePickOut | None = None


class BorrowAskPersonOut(BaseModel):
    user_id: uuid.UUID
    name: str
    username: str | None = None
    avatar_url: str | None = None


class BorrowAskOut(BaseModel):
    """One open ask to borrow. `person` is the other side: who asked, on the
    owner's list; whom you asked, on the asker's."""

    id: uuid.UUID
    person: BorrowAskPersonOut
    work_id: uuid.UUID
    edition_id: uuid.UUID
    title: str
    author: str | None = None
    cover_url: str | None = None
    created_at: datetime


class BorrowAsksOut(BaseModel):
    incoming: list[BorrowAskOut] = []
    outgoing: list[BorrowAskOut] = []
