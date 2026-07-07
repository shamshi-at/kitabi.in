"""Current-user router: read/update the signed-in user's own profile, username
availability, and score."""

import uuid

from fastapi import APIRouter, Query, status

from app.api.deps import CurrentUser, DbSession
from app.models.profile import Profile
from app.schemas.profile import (
    ProfileOut,
    ProfileUpdate,
    ScoreOut,
    UsernameAvailableOut,
    normalize_username,
)
from app.services import profile_service, scoring_service

router = APIRouter(prefix="/me", tags=["me"])


async def _profile_out(db: DbSession, profile: Profile) -> ProfileOut:
    score = await scoring_service.compute_score(db, profile.id)
    return ProfileOut.model_validate(profile).model_copy(update={"score": score["total"]})


@router.get("", response_model=ProfileOut)
async def get_me(user: CurrentUser, db: DbSession) -> ProfileOut:
    profile = await profile_service.get_profile_or_404(db, uuid.UUID(user["id"]))
    return await _profile_out(db, profile)


@router.patch("", response_model=ProfileOut)
async def update_me(patch: ProfileUpdate, user: CurrentUser, db: DbSession) -> ProfileOut:
    profile = await profile_service.get_profile_or_404(db, uuid.UUID(user["id"]))
    profile = await profile_service.update_profile(db, profile, patch)
    return await _profile_out(db, profile)


@router.get("/username-available", response_model=UsernameAvailableOut)
async def username_available(
    user: CurrentUser, db: DbSession, username: str = Query(min_length=1)
) -> UsernameAvailableOut:
    # A malformed handle is reported as unavailable rather than a 422, so an
    # as-you-type checker just shows a red state instead of erroring.
    try:
        normalized = normalize_username(username)
    except ValueError:
        return UsernameAvailableOut(username=username, available=False)
    assert normalized is not None
    available = await profile_service.is_username_available(db, normalized, uuid.UUID(user["id"]))
    return UsernameAvailableOut(username=normalized, available=available)


@router.get("/score", response_model=ScoreOut)
async def get_score(user: CurrentUser, db: DbSession) -> ScoreOut:
    breakdown = await scoring_service.compute_score(db, uuid.UUID(user["id"]))
    return ScoreOut(**breakdown)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(user: CurrentUser, db: DbSession) -> None:
    profile = await profile_service.get_profile_or_404(db, uuid.UUID(user["id"]))
    await profile_service.soft_delete_profile(db, profile)
