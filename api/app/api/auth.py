from fastapi import APIRouter

from app.api.deps import CurrentUser, DbSession
from app.models.profile import Profile
from app.schemas.profile import ProfileOut
from app.services import profile_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/bootstrap", response_model=ProfileOut)
async def bootstrap(user: CurrentUser, db: DbSession) -> Profile:
    """Create the profile row on first login. The app calls this right after
    every successful sign-in; it's a no-op if the profile already exists."""
    return await profile_service.get_or_bootstrap_profile(db, user)
