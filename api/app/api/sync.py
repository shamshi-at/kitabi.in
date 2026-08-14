"""Sync router: the offline-first push/pull protocol for Layer 2 personal data
(idempotent op push, delta pull by server_seq cursor)."""

import uuid

from fastapi import APIRouter, BackgroundTasks, Query

from app.api.deps import CurrentUser, DbSession
from app.schemas.sync import SyncPullOut, SyncPushIn, SyncPushOut
from app.services import push_service, sync_service

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push", response_model=SyncPushOut)
async def push(
    payload: SyncPushIn, user: CurrentUser, db: DbSession, background: BackgroundTasks
) -> SyncPushOut:
    user_id = uuid.UUID(user["id"])
    results = await sync_service.apply_ops(db, user_id=user_id, ops=payload.ops)

    # A note written on one device sat invisible on the other for up to the
    # 15-minute workmanager tick — the receiving side only pulls on its own
    # schedule (owner report, 14 Aug 2026). One silent nudge turns that into
    # seconds, and costs nothing but a data message: the other device drains
    # the queue it already knows how to drain, so a missed or duplicated push
    # is harmless. Scoped to notes for now — the surface where "immediately"
    # is what the reader expects, because they are mid-sitting on both.
    if any(op.entity == "reading_notes" for op in payload.ops):
        background.add_task(push_service.notify_notes_changed, user_id)

    return SyncPushOut(results=results)


@router.get("/pull", response_model=SyncPullOut)
async def pull(
    user: CurrentUser,
    db: DbSession,
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=500, ge=1, le=1000),
) -> SyncPullOut:
    return await sync_service.pull_changes(
        db, user_id=uuid.UUID(user["id"]), cursor=cursor, limit=limit
    )
