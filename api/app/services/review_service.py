"""Public reviews — every visible review on a Work, across every reader, with
the reviewer's identity resolved live from their current profile visibility.

Deliberately narrower than "every rating": a naked rating has no visibility
flag of its own (feature-map.md marks publicly-shown ratings `[LATER]`), so
this only ever surfaces a rating alongside a review its owner chose to make
public — never an anonymous rating with no accompanying text.
"""

import uuid

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Profile, Rating, Review


def _anon_name(user_id: uuid.UUID) -> str:
    """A stable placeholder for a reviewer whose profile is private — same
    reader always gets the same placeholder, so repeat reviews from them read
    as one consistent (if anonymous) voice, not a different stranger each
    time."""
    return f"User_{str(user_id).replace('-', '')[-6:].upper()}"


async def public_reviews(db: AsyncSession, work_id: uuid.UUID, limit: int = 100) -> list[dict]:
    """Visible reviews on this Work, newest first. Reviewer identity is
    computed fresh on every call, never denormalized onto the review row —
    so a profile going public (or private) is reflected the very next fetch,
    with no stale cached name to invalidate."""
    stmt = (
        select(Review, Profile, Rating.value)
        .join(Profile, Profile.id == Review.user_id)
        .outerjoin(
            Rating,
            and_(
                Rating.user_id == Review.user_id,
                Rating.work_id == Review.work_id,
                Rating.deleted_at.is_(None),
            ),
        )
        .where(
            Review.work_id == work_id,
            Review.visible.is_(True),
            Review.deleted_at.is_(None),
            Profile.deleted_at.is_(None),
        )
        .order_by(Review.created_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).unique().all()

    out = []
    for review, profile, rating_value in rows:
        public = profile.profile_visible
        if public:
            display_name = profile.full_name or (
                f"@{profile.username}" if profile.username else "A reader"
            )
        else:
            display_name = _anon_name(profile.id)
        out.append(
            {
                "id": review.id,
                "body": review.body,
                "rating": rating_value,
                "created_at": review.created_at,
                "reviewer": {
                    "id": profile.id,
                    "display_name": display_name,
                    "avatar_url": profile.avatar_url if public else None,
                    "is_public": public,
                },
            }
        )
    return out
