"""Public reviews, read from both ends: every visible review on a Work across
every reader (`public_reviews`, with the reviewer's identity resolved live from
their current profile visibility), and every visible review by one reader across
every book (`reader_reviews`, behind their profile's visibility flag).

Deliberately narrower than "every rating": a naked rating has no visibility
flag of its own (feature-map.md marks publicly-shown ratings `[LATER]`), so
this only ever surfaces a rating alongside a review its owner chose to make
public — never an anonymous rating with no accompanying text.
"""

import uuid

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Profile, Rating, Review, Work


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


async def reader_reviews(db: AsyncSession, user_id: uuid.UUID, limit: int = 50) -> list[dict]:
    """Every visible review one reader has written, newest first — the mirror
    image of `public_reviews`: there the book is fixed and the reviewer varies,
    here the reviewer is fixed and the book varies.

    Returns [] for a reader whose profile is private. `public_reviews` can fall
    back to `_anon_name` because that page is about the *book* and the reviewer
    is incidental to it; a profile page is about the reader, so anonymising
    isn't available as an answer — an attributed list of reviews IS the
    disclosure `profile_visible` exists to prevent. Both callers already 404
    the whole page for a private reader, so this is belt-and-braces: the rule
    stated where the rows are read, so a third caller can't get it wrong.

    The Work comes back as the ORM row rather than a shaped payload, because
    the two callers render different shapes from it (a `WorkCard` on the web, a
    flat item in the app). Both need `authors` and `editions`, so both are
    eagerly loaded here rather than lazily per review.
    """
    profile = (
        (
            await db.execute(
                select(Profile).where(
                    Profile.id == user_id,
                    Profile.profile_visible.is_(True),
                    Profile.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .first()
    )
    if profile is None:
        return []

    stmt = (
        select(Review, Work, Rating.value)
        .join(Work, Work.id == Review.work_id)
        .outerjoin(
            Rating,
            and_(
                Rating.user_id == Review.user_id,
                Rating.work_id == Review.work_id,
                Rating.deleted_at.is_(None),
            ),
        )
        .where(
            Review.user_id == user_id,
            Review.visible.is_(True),
            Review.deleted_at.is_(None),
            Work.deleted_at.is_(None),
        )
        .options(selectinload(Work.authors), selectinload(Work.editions))
        .order_by(Review.created_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).unique().all()
    return [
        {
            "id": review.id,
            "body": review.body,
            "rating": rating_value,
            "created_at": review.created_at,
            "work": work,
        }
        for review, work, rating_value in rows
    ]


async def rating_summary(db: AsyncSession, work_id: uuid.UUID) -> dict:
    """The community rating picture for a Work — average, total count, and a
    1-5 distribution — computed live from every rating on the work (not just
    ones attached to a public review, and not the `Work.aggregate_rating`
    column, which nothing in this codebase ever writes to). Cheap: one
    grouped COUNT, same pattern as everywhere else in this service."""
    stmt = (
        select(Rating.value, func.count())
        .where(Rating.work_id == work_id, Rating.deleted_at.is_(None))
        .group_by(Rating.value)
    )
    rows = (await db.execute(stmt)).all()
    distribution = {v: 0 for v in range(1, 6)}
    for value, count in rows:
        distribution[value] = count
    total = sum(distribution.values())
    average = sum(v * c for v, c in distribution.items()) / total if total else None
    return {"average": average, "count": total, "distribution": distribution}
