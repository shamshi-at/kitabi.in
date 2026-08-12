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

from sqlalchemy import Float, Numeric, and_, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Profile, Rating, Review, Series, Work


def _subject(model: type, work_id: uuid.UUID | None, series_id: uuid.UUID | None):  # noqa: ANN201
    """The "which subject is this row about?" predicate, in one place.

    A rating or review names exactly one of a Work or a Series (migration
    000044). Every read goes through here so no caller can accidentally ask a
    question that spans both pools — "the average rating" of a series and of
    its volumes are different numbers, and mixing them is the one failure this
    design exists to prevent.
    """
    if (work_id is None) == (series_id is None):
        raise ValueError("exactly one of work_id or series_id is required")
    return model.work_id == work_id if work_id is not None else model.series_id == series_id


def _anon_name(user_id: uuid.UUID) -> str:
    """A stable placeholder for a reviewer whose profile is private — same
    reader always gets the same placeholder, so repeat reviews from them read
    as one consistent (if anonymous) voice, not a different stranger each
    time."""
    return f"User_{str(user_id).replace('-', '')[-6:].upper()}"


async def public_reviews(
    db: AsyncSession,
    work_id: uuid.UUID | None = None,
    limit: int = 100,
    *,
    series_id: uuid.UUID | None = None,
) -> list[dict]:
    """Visible reviews on one subject — a Work or a Series — newest first.

    Reviewer identity is computed fresh on every call, never denormalized onto
    the review row, so a profile going public (or private) is reflected the very
    next fetch with no stale cached name to invalidate.

    The rating shown beside a review is the one that reader gave *this same
    subject*: a reader who loved the saga but found volume 2 a slog has two
    honest numbers, and pairing a series review with a book rating would print
    a figure they never gave.
    """
    subject_is_work = work_id is not None
    rating_matches_subject = (
        Rating.work_id == Review.work_id
        if subject_is_work
        else Rating.series_id == Review.series_id
    )
    stmt = (
        select(Review, Profile, Rating.value)
        .join(Profile, Profile.id == Review.user_id)
        .outerjoin(
            Rating,
            and_(
                Rating.user_id == Review.user_id,
                rating_matches_subject,
                Rating.deleted_at.is_(None),
            ),
        )
        .where(
            _subject(Review, work_id, series_id),
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
    out = [
        {
            "id": review.id,
            "body": review.body,
            "rating": rating_value,
            "created_at": review.created_at,
            "work": work,
            "series": None,
        }
        for review, work, rating_value in rows
    ]

    # …and the ones they wrote about a series. Fetched separately rather than
    # bolted onto the query above: the join target differs, and an outer join to
    # both would return a row of mostly-NULLs for every review. A review the
    # reader wrote is theirs whatever its subject — leaving series reviews out
    # of their own profile would be the same silent omission as leaving a
    # co-author off a byline.
    series_stmt = (
        select(Review, Series, Rating.value)
        .join(Series, Series.id == Review.series_id)
        .outerjoin(
            Rating,
            and_(
                Rating.user_id == Review.user_id,
                Rating.series_id == Review.series_id,
                Rating.deleted_at.is_(None),
            ),
        )
        .where(
            Review.user_id == user_id,
            Review.visible.is_(True),
            Review.deleted_at.is_(None),
            Series.deleted_at.is_(None),
        )
        .order_by(Review.created_at.desc())
        .limit(limit)
    )
    out += [
        {
            "id": review.id,
            "body": review.body,
            "rating": rating_value,
            "created_at": review.created_at,
            "work": None,
            "series": series,
        }
        for review, series, rating_value in (await db.execute(series_stmt)).unique().all()
    ]
    out.sort(key=lambda r: r["created_at"], reverse=True)
    return out[:limit]


async def refresh_aggregate_rating(db: AsyncSession, work_id: uuid.UUID) -> None:
    """Write the live average onto `Work.aggregate_rating`.

    Until 9 Aug 2026 nothing ever wrote this column, so five orderings and
    every WorkCard read permanent NULL — "Top rated" sorted correctly (it
    computes live) while the cards it fronted couldn't show a figure. Sync is
    the only writer of ratings, so calling this on every applied rating op
    keeps the denormalized column honest; migration 000042 backfilled it.
    Round to 2 like `rating_summary` so the two never disagree visibly."""
    live_avg = (
        select(func.round(func.avg(Rating.value).cast(Numeric), 2).cast(Float))
        .where(Rating.work_id == work_id, Rating.deleted_at.is_(None))
        .scalar_subquery()
    )
    await db.execute(update(Work).where(Work.id == work_id).values(aggregate_rating=live_avg))


async def rating_summary(
    db: AsyncSession, work_id: uuid.UUID | None = None, *, series_id: uuid.UUID | None = None
) -> dict:
    """The community rating picture for one subject — a Work or a Series:
    average, total count, and a 1-5 distribution, computed live from every
    rating on that subject (not just ones attached to a public review). Cheap:
    one grouped COUNT, same pattern as everywhere else in this service.

    A series and its volumes have separate pools by construction — a rating row
    names one or the other — so this never has to subtract one from the other.
    """
    stmt = (
        select(Rating.value, func.count())
        .where(_subject(Rating, work_id, series_id), Rating.deleted_at.is_(None))
        .group_by(Rating.value)
    )
    rows = (await db.execute(stmt)).all()
    distribution = {v: 0 for v in range(1, 6)}
    for value, count in rows:
        distribution[value] = count
    total = sum(distribution.values())
    average = sum(v * c for v, c in distribution.items()) / total if total else None
    return {"average": average, "count": total, "distribution": distribution}
