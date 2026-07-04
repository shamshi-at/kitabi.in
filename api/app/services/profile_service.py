import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.profile import Profile
from app.schemas.profile import ProfileUpdate


async def get_or_bootstrap_profile(db: AsyncSession, user: dict) -> Profile:
    """Fetch the profile for this auth user, creating it on first login.

    Idempotent — the client calls this on every sign-in, not just the first.
    """
    user_id = uuid.UUID(user["id"])
    profile = await db.get(Profile, user_id)
    if profile is not None:
        return profile
    profile = Profile(
        id=user_id,
        email=user["email"],
        full_name=user.get("full_name"),
        avatar_url=user.get("avatar_url"),
    )
    db.add(profile)
    await db.commit()
    await db.refresh(profile)
    return profile


async def get_profile_or_404(db: AsyncSession, user_id: uuid.UUID) -> Profile:
    profile = await db.get(Profile, user_id)
    if profile is None or profile.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_bootstrapped", "message": "Call POST /auth/bootstrap first"},
        )
    return profile


async def update_profile(db: AsyncSession, profile: Profile, patch: ProfileUpdate) -> Profile:
    for field, value in patch.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    await db.commit()
    await db.refresh(profile)
    return profile


async def soft_delete_profile(db: AsyncSession, profile: Profile) -> None:
    profile.deleted_at = datetime.now(UTC)
    await db.commit()
