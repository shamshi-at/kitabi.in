"""Pydantic request/response schemas for the sync push/pull protocol
(per-op push payloads, results, and server_seq-cursored pull deltas)."""

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

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


class RatingCreate(BaseModel):
    id: uuid.UUID
    work_id: uuid.UUID
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


class ReadingSessionUpdate(BaseModel):
    # Sent by the client's duplicate-entry heal, re-pointing sessions from a
    # merged-away library entry onto the kept one. Ownership of the target
    # entry is validated in apply (same _refs_owned check as create).
    library_entry_id: uuid.UUID | None = None
    ended_at: datetime | None = None
    duration_seconds: int | None = Field(default=None, ge=0)
    page_start: int | None = None
    page_end: int | None = None


class ReviewCreate(BaseModel):
    id: uuid.UUID
    work_id: uuid.UUID
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
