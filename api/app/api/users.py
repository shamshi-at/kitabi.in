"""Users router: search other users' public profiles (for connections/lending)."""

import uuid

from fastapi import APIRouter, Query

from app.api.catalog import work_summary
from app.api.deps import CurrentUser, DbSession
from app.schemas.catalog import WorkSummaryOut
from app.schemas.profile import PublicLibraryItemOut, PublicProfileOut, UserSearchOut
from app.services import catalog_service, connection_service, profile_service, scoring_service

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/search", response_model=list[UserSearchOut])
async def search_users(
    user: CurrentUser, db: DbSession, q: str = Query(min_length=1)
) -> list[UserSearchOut]:
    """Find a reader by username to lend to. Only users who've set a username
    are findable; the caller is excluded from their own results."""
    profiles = await profile_service.search_users(db, q, uuid.UUID(user["id"]))
    return [UserSearchOut.model_validate(p) for p in profiles]


@router.get("/{user_id}/profile", response_model=PublicProfileOut)
async def public_profile(user_id: uuid.UUID, user: CurrentUser, db: DbSession) -> PublicProfileOut:
    """Another reader's public profile — 404 unless they've kept it public
    (the default). Carries the flag telling the app whether their library
    may be fetched too."""
    profile = await profile_service.get_public_profile(db, user_id)
    score = await scoring_service.compute_score(db, user_id)
    connections_count = await connection_service.count_accepted(db, user_id)
    return PublicProfileOut(
        id=profile.id,
        username=profile.username,
        full_name=profile.full_name,
        avatar_url=profile.avatar_url,
        score=score["total"],
        books_tracked=score["books_tracked"],
        books_finished=score["books_finished"],
        library_visible=profile.library_visible,
        connections_count=connections_count,
    )


@router.get("/{user_id}/library", response_model=list[PublicLibraryItemOut])
async def public_library(
    user_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> list[PublicLibraryItemOut]:
    """The books on a reader's public shelf — 404 unless both their profile
    and library are public."""
    items = await profile_service.public_library(db, user_id)
    return [PublicLibraryItemOut(**item) for item in items]


@router.get("/{user_id}/works", response_model=list[WorkSummaryOut])
async def public_works(
    user_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> list[WorkSummaryOut]:
    """The "Works" tab on a reader's public profile — every catalog Work
    whose author is linked to this profile. Gated only on `profile_visible`,
    independent of `library_visible`: a private reader can still be a public
    author."""
    await profile_service.get_public_profile(db, user_id)
    works = await catalog_service.works_by_linked_author(db, user_id)
    return [work_summary(w) for w in works]
