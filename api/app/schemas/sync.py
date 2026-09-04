"""Pydantic request/response schemas for the sync push/pull protocol
(per-op push payloads, results, and server_seq-cursored pull deltas)."""

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

# Entities the client can push. `activity_log_entries` is pull-only — it's
# written server-side as a side effect of other ops, never created directly.
PushEntity = Literal[
    "library_entries",
    "ratings",
    "reviews",
    "personal_tags",
    "library_entry_tags",
    "lending_records",
    "reading_sessions",
    "reading_notes",
]
PullEntity = PushEntity | Literal["activity_log_entries"]
OpType = Literal["create", "update", "delete"]

MAX_OPS_PER_PUSH = 200


class SyncOpIn(BaseModel):
    op_id: uuid.UUID
    device_id: uuid.UUID
    entity: PushEntity
    entity_id: uuid.UUID
    op_type: OpType
    payload: dict[str, Any] = {}


class SyncPushIn(BaseModel):
    ops: list[SyncOpIn] = Field(min_length=1, max_length=MAX_OPS_PER_PUSH)


class SyncOpResult(BaseModel):
    op_id: uuid.UUID
    status: Literal["applied", "duplicate", "rejected"]
    code: str | None = None
    server_seq: int | None = None


class SyncPushOut(BaseModel):
    results: list[SyncOpResult]


class SyncChange(BaseModel):
    entity: PullEntity
    data: dict[str, Any]


class SyncPullOut(BaseModel):
    changes: list[SyncChange]
    next_cursor: int
    has_more: bool


# --- Per-entity create/update payload shapes, validated inside apply_ops ---


class LibraryEntryCreate(BaseModel):
    id: uuid.UUID
    edition_id: uuid.UUID
    status: str = "pending"
    ownership: str = "owned"
    start_date: date | None = None
    finish_date: date | None = None
    current_page: int | None = None
    is_favorite: bool = False
    notes: str | None = None


class LibraryEntryUpdate(BaseModel):
    status: str | None = None
    # Only ever sent 'owned' — the reader "buying" a book they'd been
    # borrowing (see library_entry.py). Nothing flips a row back to
    # 'borrowed' after creation.
    ownership: str | None = None
    start_date: date | None = None
    finish_date: date | None = None
    current_page: int | None = None
    is_favorite: bool | None = None
    notes: str | None = None


class _OneSubject(BaseModel):
    """A rating or review names exactly one subject: a book or a series.

    Checked here as well as by the database constraint so a malformed op comes
    back as `invalid_payload` against that one op — a raw IntegrityError would
    surface as a 500 and take the whole push batch down with it, which is how a
    single bad row once cost a device every queued change (CLAUDE.md,
    7 Jul 2026).
    """

    work_id: uuid.UUID | None = None
    series_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def _exactly_one_subject(self):  # noqa: ANN201
        if (self.work_id is None) == (self.series_id is None):
            raise ValueError("exactly one of work_id or series_id is required")
        return self


class RatingCreate(_OneSubject):
    id: uuid.UUID
    value: int = Field(ge=1, le=5)


class RatingUpdate(BaseModel):
    value: int | None = Field(default=None, ge=1, le=5)


class ReadingSessionCreate(BaseModel):
    id: uuid.UUID
    library_entry_id: uuid.UUID
    started_at: datetime
    ended_at: datetime
    duration_seconds: int = Field(ge=0)
    page_start: int | None = None
    page_end: int | None = None
    auto_stopped: bool = False
    # The pass this sitting belongs to. Nullable for the same reason as on a
    # note: back-filled rows and older app versions both arrive without it.
    read_id: uuid.UUID | None = None


class ReadingSessionUpdate(BaseModel):
    # Sent by the client's duplicate-entry heal, re-pointing sessions from a
    # merged-away library entry onto the kept one. Ownership of the target
    # entry is validated in apply (same _refs_owned check as create).
    library_entry_id: uuid.UUID | None = None
    ended_at: datetime | None = None
    duration_seconds: int | None = Field(default=None, ge=0)
    page_start: int | None = None
    page_end: int | None = None
    # Sent by the reader's own correction of an auto-stopped sitting's ended_at
    # / page_end — never re-set to true from the client.
    auto_stopped: bool | None = None
    read_id: uuid.UUID | None = None


class ReadCreate(BaseModel):
    """One pass through a book (CLAUDE.md rule 19).

    No `ordinal`: position is derived by ordering an entry's reads on
    `start_date`, so two devices that begin a re-read offline converge instead
    of both writing "third". Dates, not datetimes — a read begins and ends on a
    day, and a `date` field only accepts a datetime string whose time part is
    zero (the 16 Jul 2026 lesson), so the wire format is YYYY-MM-DD.
    """

    id: uuid.UUID
    library_entry_id: uuid.UUID
    status: str = "reading"
    start_date: date | None = None
    finish_date: date | None = None
    current_page: int | None = Field(default=None, ge=0)


class ReadUpdate(BaseModel):
    status: str | None = None
    start_date: date | None = None
    finish_date: date | None = None
    current_page: int | None = Field(default=None, ge=0)


class ReadingNoteCreate(BaseModel):
    id: uuid.UUID
    library_entry_id: uuid.UUID
    # Optional: a note doesn't need a sitting ("lent to mom, she folds pages").
    session_id: uuid.UUID | None = None
    # The pass this thought belongs to. Nullable because rows written before
    # 29 Aug 2026 are stamped by the backfill, and because an app version that
    # predates reads pushes without it.
    read_id: uuid.UUID | None = None
    body: str
    # A passage carries both; a moment carries only page_start; a thought
    # about the book carries neither.
    page_start: int | None = Field(default=None, ge=1)
    page_end: int | None = Field(default=None, ge=1)


class ReadingNoteUpdate(BaseModel):
    body: str | None = None
    session_id: uuid.UUID | None = None
    read_id: uuid.UUID | None = None
    page_start: int | None = Field(default=None, ge=1)
    page_end: int | None = Field(default=None, ge=1)


class ReviewCreate(_OneSubject):
    id: uuid.UUID
    body: str
    visible: bool = False


class ReviewUpdate(BaseModel):
    body: str | None = None
    visible: bool | None = None


class PersonalTagCreate(BaseModel):
    id: uuid.UUID
    name: str


class PersonalTagUpdate(BaseModel):
    name: str | None = None


class LibraryEntryTagCreate(BaseModel):
    id: uuid.UUID
    library_entry_id: uuid.UUID
    tag_id: uuid.UUID


class LibraryEntryTagUpdate(BaseModel):
    """Assignments are create/delete only — nothing on one is ever patched."""


class LendingRecordCreate(BaseModel):
    id: uuid.UUID
    direction: str = "lent"
    library_entry_id: uuid.UUID | None = None
    edition_id: uuid.UUID | None = None
    borrower_name: str
    borrower_user_id: uuid.UUID | None = None
    linked_loan_id: uuid.UUID | None = None
    lent_date: date
    due_date: date | None = None
    returned_date: date | None = None
    note: str | None = None


class LendingRecordUpdate(BaseModel):
    # Sent by the client's duplicate-entry heal (see ReadingSessionUpdate).
    library_entry_id: uuid.UUID | None = None
    borrower_name: str | None = None
    # Sent (possibly as null) when a rejected loan is unlinked to a private
    # contact — clearing the Kitabi user reference. Explicit-null clears it.
    borrower_user_id: uuid.UUID | None = None
    due_date: date | None = None
    returned_date: date | None = None
    note: str | None = None
