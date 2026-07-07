"""Sync router: the offline-first push/pull protocol for Layer 2 personal data
(idempotent op push, delta pull by server_seq cursor)."""

import uuid

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, DbSession
from app.schemas.sync import SyncPullOut, SyncPushIn, SyncPushOut
from app.services import sync_service

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push", response_model=SyncPushOut)
async def push(payload: SyncPushIn, user: CurrentUser, db: DbSession) -> SyncPushOut:
    results = await sync_service.apply_ops(db, user_id=uuid.UUID(user["id"]), ops=payload.ops)
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
