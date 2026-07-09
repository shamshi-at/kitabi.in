"""Sync push/pull for Layer 2 (personal) data — the only path user records take to
the server. Idempotent op application keyed by client op UUID, delete-wins then
last-write-wins conflict resolution (losers written to ConflictHistory), and a
server_seq bigserial pull cursor bumped on every mutation. Lending ops fan out to
lend_mirror_service after commit (CLAUDE.md rules 1, 6, sync-engine notes)."""

import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

from pydantic import BaseModel, ValidationError
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.inspection import inspect

from app.models import (
    ActivityLogEntry,
    ConflictHistory,
    LendingRecord,
    LibraryEntry,
    LibraryEntryTag,
    PersonalTag,
    Rating,
    ReadingSession,
    Review,
    SyncOp,
)
from app.schemas.sync import (
    LendingRecordCreate,
    LendingRecordUpdate,
    LibraryEntryCreate,
    LibraryEntryTagCreate,
    LibraryEntryTagUpdate,
    LibraryEntryUpdate,
    PersonalTagCreate,
    PersonalTagUpdate,
    RatingCreate,
    RatingUpdate,
    ReadingSessionCreate,
    ReadingSessionUpdate,
    ReviewCreate,
    ReviewUpdate,
    SyncChange,
    SyncOpIn,
    SyncOpResult,
    SyncPullOut,
)
from app.services import lend_mirror_service

logger = logging.getLogger(__name__)

CONFLICT_RETENTION = timedelta(days=30)

# entity name -> (model, create_schema, update_schema)
ENTITIES: dict[str, tuple[type, type[BaseModel], type[BaseModel]]] = {
    "library_entries": (LibraryEntry, LibraryEntryCreate, LibraryEntryUpdate),
    "ratings": (Rating, RatingCreate, RatingUpdate),
    "reviews": (Review, ReviewCreate, ReviewUpdate),
    "personal_tags": (PersonalTag, PersonalTagCreate, PersonalTagUpdate),
    "library_entry_tags": (LibraryEntryTag, LibraryEntryTagCreate, LibraryEntryTagUpdate),
    "lending_records": (LendingRecord, LendingRecordCreate, LendingRecordUpdate),
    "reading_sessions": (ReadingSession, ReadingSessionCreate, ReadingSessionUpdate),
}
# Pull also serves activity_log_entries, which the client never pushes.
PULL_MODELS: dict[str, type] = {
    **{k: v[0] for k, v in ENTITIES.items()},
    "activity_log_entries": ActivityLogEntry,
}


@dataclass
class _ConflictData:
    rule: str
    entity: str
    entity_id: uuid.UUID
    winning_payload: dict[str, Any]
    discarded_payload: dict[str, Any]


def _row_to_dict(row: Any) -> dict[str, Any]:
    mapper = inspect(row).mapper
    out: dict[str, Any] = {}
    for column in mapper.columns:
        value = getattr(row, column.key)
        # `date` covers datetime too (subclass) — both must serialize, or a
        # conflict-history write on a row with a plain date column (lent_date,
        # start_date…) blows up the whole push batch with a 500.
        if isinstance(value, date):
            out[column.key] = value.isoformat()
        elif isinstance(value, uuid.UUID):
            out[column.key] = str(value)
        else:
            out[column.key] = value
    return out


async def _bump_seq(db: AsyncSession, row: Any) -> None:
    """A column `server_default` only fires on INSERT — Postgres doesn't
    re-evaluate it on UPDATE. Every mutation (create/update/delete) needs a
    fresh, monotonically-later server_seq so the pull cursor stays correct,
    so this explicitly pulls the next value every time, mirroring
    rupee-diary's reference implementation."""
    row.server_seq = text("nextval('sync_seq')")
    await db.flush()
    await db.refresh(row, ["server_seq"])


async def _last_device(db: AsyncSession, entity: str, entity_id: uuid.UUID) -> uuid.UUID | None:
    """The device_id of the most recently applied create/update op on this
    row — the same-user analogue of rupee-diary's "last applier" check,
    since Kitabi has one user but potentially several devices."""
    stmt = (
        select(SyncOp.device_id)
        .where(
            SyncOp.entity == entity,
            SyncOp.entity_id == entity_id,
            SyncOp.op_type.in_(("create", "update")),
            SyncOp.status == "applied",
        )
        .order_by(SyncOp.applied_at.desc())
        .limit(1)
    )
    return (await db.execute(stmt)).scalar_one_or_none()


def _activity_for(entity: str, op_type: str, row: Any, previous_status: str | None) -> dict | None:
    """[WIRED] — a handful of meaningful events, not an exhaustive audit
    log (feature-map.md rule 15: "your own events," not every field edit)."""
    if entity == "library_entries" and op_type == "create":
        return {"event_type": "added_book", "entity_type": "library_entry", "entity_id": row.id}
    if entity == "library_entries" and op_type == "update":
        if previous_status != "read" and row.status == "read":
            return {
                "event_type": "finished_book",
                "entity_type": "library_entry",
                "entity_id": row.id,
            }
        return None
    if entity == "ratings" and op_type == "create":
        return {
            "event_type": "rated_book",
            "entity_type": "rating",
            "entity_id": row.id,
            "payload": {"work_id": str(row.work_id), "value": row.value},
        }
    if entity == "reviews" and op_type == "create":
        return {"event_type": "wrote_review", "entity_type": "review", "entity_id": row.id}
    if entity == "lending_records" and op_type == "create":
        return {"event_type": "lent_book", "entity_type": "lending_record", "entity_id": row.id}
    return None


async def _log_activity(db: AsyncSession, user_id: uuid.UUID, activity: dict) -> None:
    entry = ActivityLogEntry(
        user_id=user_id,
        event_type=activity["event_type"],
        entity_type=activity["entity_type"],
        entity_id=activity["entity_id"],
        payload=activity.get("payload", {}),
        occurred_at=datetime.now(UTC),
    )
    db.add(entry)
    await db.flush()
    await db.refresh(entry, ["server_seq"])


async def _refs_owned(db: AsyncSession, user_id: uuid.UUID, entity: str, data: dict) -> bool:
    """Referenced Layer-2 rows must belong to the pusher. The FK constraint only
    proves the row *exists* — without this check a crafted create could hang a
    lending record or tag assignment off another user's library entry/tag."""
    if entity in ("lending_records", "reading_sessions"):
        entry_id = data.get("library_entry_id")
        if entry_id is not None:
            entry = await db.get(LibraryEntry, entry_id)
            if entry is None or entry.user_id != user_id:
                return False
    elif entity == "library_entry_tags":
        entry = await db.get(LibraryEntry, data["library_entry_id"])
        if entry is None or entry.user_id != user_id:
            return False
        tag = await db.get(PersonalTag, data["tag_id"])
        if tag is None or tag.user_id != user_id:
            return False
    return True


async def _apply_one(
    db: AsyncSession, user_id: uuid.UUID, op: SyncOpIn
) -> tuple[SyncOpResult, _ConflictData | None, dict | None]:
    model, create_schema, update_schema = ENTITIES[op.entity]
    row = await db.get(model, op.entity_id)

    if op.op_type == "create":
        if row is not None:
            return (
                SyncOpResult(op_id=op.op_id, status="duplicate", server_seq=row.server_seq),
                None,
                None,
            )
        data = create_schema.model_validate({**op.payload, "id": op.entity_id})
        if not await _refs_owned(db, user_id, op.entity, data.model_dump()):
            return (
                SyncOpResult(op_id=op.op_id, status="rejected", code="invalid_reference"),
                None,
                None,
            )
        row = model(**data.model_dump(), user_id=user_id)
        db.add(row)
        await db.flush()
        await db.refresh(row, ["server_seq"])
        activity = _activity_for(op.entity, "create", row, None)
        return (
            SyncOpResult(op_id=op.op_id, status="applied", server_seq=row.server_seq),
            None,
            activity,
        )

    if row is None or row.user_id != user_id:
        return SyncOpResult(op_id=op.op_id, status="rejected", code="not_found"), None, None

    if op.op_type == "delete":
        if row.deleted_at is None:
            row.deleted_at = datetime.now(UTC)
            await _bump_seq(db, row)
        return SyncOpResult(op_id=op.op_id, status="applied", server_seq=row.server_seq), None, None

    # op_type == "update"
    if row.deleted_at is not None:
        conflict = _ConflictData(
            rule="delete_wins",
            entity=op.entity,
            entity_id=op.entity_id,
            winning_payload={"deleted": True, "entity_id": str(op.entity_id)},
            discarded_payload=op.payload,
        )
        return SyncOpResult(op_id=op.op_id, status="rejected", code="deleted_wins"), conflict, None

    previous_status = getattr(row, "status", None)
    last_device = await _last_device(db, op.entity, op.entity_id)
    conflict = None
    if last_device is not None and last_device != op.device_id:
        conflict = _ConflictData(
            rule="last_write_wins",
            entity=op.entity,
            entity_id=op.entity_id,
            winning_payload=op.payload,
            discarded_payload=_row_to_dict(row),
        )

    data = update_schema.model_validate(op.payload)
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(row, key, value)
    row.updated_at = datetime.now(UTC)
    await _bump_seq(db, row)

    activity = _activity_for(op.entity, "update", row, previous_status)
    return (
        SyncOpResult(op_id=op.op_id, status="applied", server_seq=row.server_seq),
        conflict,
        activity,
    )


async def apply_ops(
    db: AsyncSession, user_id: uuid.UUID, ops: list[SyncOpIn]
) -> list[SyncOpResult]:
    results: list[SyncOpResult] = []
    # Lending records that applied — mirrored onto the borrower's account after
    # the main commit (so a mirror failure can't reject the lender's own op).
    lending_applied: list[uuid.UUID] = []

    for op in ops:
        existing_op = await db.get(SyncOp, op.op_id)
        if existing_op is not None:
            status = "duplicate" if existing_op.status == "applied" else "rejected"
            results.append(SyncOpResult(op_id=op.op_id, status=status))
            continue

        try:
            async with db.begin_nested():
                result, conflict, activity = await _apply_one(db, user_id, op)
        except IntegrityError:
            result, conflict, activity = (
                SyncOpResult(op_id=op.op_id, status="rejected", code="invalid_reference"),
                None,
                None,
            )
        except ValidationError:
            result, conflict, activity = (
                SyncOpResult(op_id=op.op_id, status="rejected", code="invalid_payload"),
                None,
                None,
            )

        db.add(
            SyncOp(
                op_id=op.op_id,
                user_id=user_id,
                device_id=op.device_id,
                entity=op.entity,
                entity_id=op.entity_id,
                op_type=op.op_type,
                status=result.status,
            )
        )
        await db.flush()

        if conflict is not None:
            await _persist_conflict(db, user_id, conflict)
        if activity is not None:
            await _log_activity(db, user_id, activity)
        if op.entity == "lending_records" and result.status == "applied":
            lending_applied.append(op.entity_id)

        results.append(result)

    await db.commit()

    # Fan applied lending ops out to the counterparty (lender→borrower mirror,
    # borrower→lender return reflection) — best-effort, each isolated so one
    # failure never affects the pusher's committed ops. Logged loudly: a silent
    # miss here is exactly "user B never sees the return".
    for record_id in lending_applied:
        try:
            await lend_mirror_service.mirror_lending(db, user_id, record_id)
        except Exception:  # noqa: BLE001 — mirroring is a side effect, never fatal
            logger.exception(
                "lend mirror failed for lending_record %s pushed by user %s",
                record_id,
                user_id,
            )
            await db.rollback()

    return results


async def _persist_conflict(db: AsyncSession, user_id: uuid.UUID, conflict: _ConflictData) -> None:
    now = datetime.now(UTC)
    db.add(
        ConflictHistory(
            user_id=user_id,
            entity=conflict.entity,
            entity_id=conflict.entity_id,
            rule=conflict.rule,
            winning_payload=conflict.winning_payload,
            discarded_payload=conflict.discarded_payload,
            occurred_at=now,
            expires_at=now + CONFLICT_RETENTION,
        )
    )
    await db.flush()


async def pull_changes(
    db: AsyncSession, user_id: uuid.UUID, cursor: int, limit: int = 500
) -> SyncPullOut:
    changes: list[tuple[int, SyncChange]] = []

    for entity, model in PULL_MODELS.items():
        stmt = (
            select(model)
            .where(model.user_id == user_id, model.server_seq > cursor)
            .order_by(model.server_seq)
            .limit(limit + 1)
        )
        rows = (await db.execute(stmt)).scalars().all()
        changes.extend(
            (r.server_seq, SyncChange(entity=entity, data=_row_to_dict(r))) for r in rows
        )

    changes.sort(key=lambda pair: pair[0])
    page = changes[:limit]
    has_more = len(changes) > limit
    next_cursor = page[-1][0] if page else cursor
    return SyncPullOut(changes=[c for _, c in page], next_cursor=next_cursor, has_more=has_more)
