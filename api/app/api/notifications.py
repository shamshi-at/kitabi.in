"""In-app inbox router — the bell on Home: what a reader was notified about,
read state, and clearing (services/inbox_service.py)."""

import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.inbox import InboxOut, MarkReadIn, UnreadOut
from app.services import inbox_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=InboxOut)
async def list_notifications(user: CurrentUser, db: DbSession) -> InboxOut:
    """Newest first, with the unread count."""
    return await inbox_service.list_for(db, uuid.UUID(user["id"]))


@router.get("/unread", response_model=UnreadOut)
async def unread(user: CurrentUser, db: DbSession) -> UnreadOut:
    """Just the badge number — Home asks this on every visit, so it stays tiny."""
    return UnreadOut(unread=await inbox_service.unread_count(db, uuid.UUID(user["id"])))


@router.post("/read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_read(payload: MarkReadIn, user: CurrentUser, db: DbSession) -> None:
    await inbox_service.mark_read(db, uuid.UUID(user["id"]), payload.ids)


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
async def mark_all_read(user: CurrentUser, db: DbSession) -> None:
    await inbox_service.mark_read(db, uuid.UUID(user["id"]), None)


@router.post("/clear", status_code=status.HTTP_204_NO_CONTENT)
async def clear(user: CurrentUser, db: DbSession) -> None:
    await inbox_service.clear(db, uuid.UUID(user["id"]))
