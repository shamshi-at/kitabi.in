import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DbSession
from app.models.profile import Profile
from app.schemas.profile import ProfileOut, ProfileUpdate
from app.services import profile_service

router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=ProfileOut)
async def get_me(user: CurrentUser, db: DbSession) -> Profile:
    return await profile_service.get_profile_or_404(db, uuid.UUID(user["id"]))


@router.patch("", response_model=ProfileOut)
async def update_me(patch: ProfileUpdate, user: CurrentUser, db: DbSession) -> Profile:
    profile = await profile_service.get_profile_or_404(db, uuid.UUID(user["id"]))
    return await profile_service.update_profile(db, profile, patch)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(user: CurrentUser, db: DbSession) -> None:
    profile = await profile_service.get_profile_or_404(db, uuid.UUID(user["id"]))
    await profile_service.soft_delete_profile(db, profile)
