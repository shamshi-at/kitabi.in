"""User profile business logic — bootstrap a profile on first login from the auth
JWT, then update username/display fields with visibility toggles wired throughout
(CLAUDE.md rule 16), enforcing case-insensitive username uniqueness."""

import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
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
        # Re-created account: a prior in-app "delete account" soft-deleted this
        # profile (same Supabase user id). Revive it on re-bootstrap — otherwise
        # /me and PATCH /me keep 404ing (get_profile_or_404 rejects deleted rows)
        # and the reader is stuck at onboarding, unable to get back in.
        if profile.deleted_at is not None:
            profile.deleted_at = None
            profile.email = user["email"]
            await db.commit()
            await db.refresh(profile)
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
    try:
        await db.commit()
    except IntegrityError as exc:
        # The only uniqueness constraint on profiles is the username handle.
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "username_taken", "message": "That username is already taken"},
        ) from exc
    await db.refresh(profile)
    return profile


async def is_username_available(
    db: AsyncSession, username: str, exclude_user_id: uuid.UUID
) -> bool:
    """Case-insensitive availability check (usernames are stored lowercased).
    A user's own current handle counts as available to them."""
    stmt = select(Profile.id).where(
        func.lower(Profile.username) == username.lower(),
        Profile.id != exclude_user_id,
        Profile.deleted_at.is_(None),
    )
    return (await db.execute(stmt)).first() is None


async def search_users(
    db: AsyncSession, query: str, exclude_user_id: uuid.UUID, limit: int = 10
) -> list[Profile]:
    """Find readers by username prefix — only users who've set one are findable
    (username is the opt-in to being lend-to-able). Excludes the caller."""
    stmt = (
        select(Profile)
        .where(
            Profile.username.is_not(None),
            Profile.username.ilike(f"{query.strip().lower()}%"),
            Profile.id != exclude_user_id,
            Profile.deleted_at.is_(None),
        )
        .order_by(Profile.username)
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


async def get_public_profile(db: AsyncSession, target_id: uuid.UUID) -> Profile:
    """Another reader's profile, only if they've kept it public (the default).
    Private and non-existent look identical (404) — visibility must not leak
    existence."""
    profile = await db.get(Profile, target_id)
    if profile is None or profile.deleted_at is not None or not profile.profile_visible:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Profile not found"},
        )
    return profile


async def public_library(db: AsyncSession, target_id: uuid.UUID, limit: int = 200) -> list[dict]:
    """The books on a reader's public shelf — gated on BOTH profile and
    library visibility (a public library behind a private profile would leak
    it). Newest additions first, catalog identity + status per book."""
    profile = await get_public_profile(db, target_id)
    if not profile.library_visible:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Library not public"},
        )
    from app.models import Edition, LibraryEntry, Work  # local import: avoids a module cycle

    stmt = (
        select(LibraryEntry, Edition, Work)
        .join(Edition, Edition.id == LibraryEntry.edition_id)
        .join(Work, Work.id == Edition.work_id)
        .where(LibraryEntry.user_id == target_id, LibraryEntry.deleted_at.is_(None))
        .order_by(LibraryEntry.created_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).unique().all()
    return [
        {
            "work_id": work.id,
            "edition_id": edition.id,
            "title": work.title,
            "author_names": ", ".join(a.name for a in work.authors),
            "cover_url": edition.cover_url,
            "status": entry.status,
        }
        for entry, edition, work in rows
    ]


async def soft_delete_profile(db: AsyncSession, profile: Profile) -> None:
    profile.deleted_at = datetime.now(UTC)
    await db.commit()
