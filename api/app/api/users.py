"""Users router: search other users' public profiles (for connections/lending)."""

import uuid

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, DbSession
from app.schemas.profile import UserSearchOut
from app.services import profile_service

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/search", response_model=list[UserSearchOut])
async def search_users(
    user: CurrentUser, db: DbSession, q: str = Query(min_length=1)
) -> list[UserSearchOut]:
    """Find a reader by username to lend to. Only users who've set a username
    are findable; the caller is excluded from their own results."""
    profiles = await profile_service.search_users(db, q, uuid.UUID(user["id"]))
    return [UserSearchOut.model_validate(p) for p in profiles]
