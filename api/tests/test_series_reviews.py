"""Rating and reviewing a series, and the books inside it, independently.

The rule these exist to protect: **a series and its volumes have separate
pools.** "The saga is worth reading" and "volume 3 drags" are different claims,
and a reader who makes both should see both numbers rather than one blended
figure that is true of neither. A single table carries both subjects, so the
isolation is a constraint plus a filter — and a filter is exactly the kind of
thing that gets forgotten, which is why it is pinned from both directions here.
"""

import uuid

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import Profile, Rating, Review, Series, Work
from app.services import review_service, slug_service


async def _series(db, name="Ponniyin Selvan") -> Series:
    row = Series(name=name)
    db.add(row)
    await db.flush()
    await slug_service.ensure_slug(db, row)
    return row


async def _work(db, title="Sulathirai", **kw) -> Work:
    row = Work(title=title, **kw)
    db.add(row)
    await db.flush()
    await slug_service.ensure_slug(db, row)
    return row


def _rating(user_id, value, *, work=None, series=None) -> Rating:
    return Rating(
        id=uuid.uuid4(),
        user_id=user_id,
        value=value,
        work_id=work.id if work else None,
        series_id=series.id if series else None,
    )


async def _profile(db, user_id, *, visible=True) -> Profile:
    """public_reviews inner-joins Profile — a reviewer with no profile row has
    no reviews as far as every read path is concerned."""
    row = await db.get(Profile, uuid.UUID(user_id))
    if row is None:
        row = Profile(id=uuid.UUID(user_id), email="tester@example.com")
        db.add(row)
    row.profile_visible = visible
    await db.flush()
    return row


def _review(user_id, body, *, work=None, series=None, visible=True) -> Review:
    return Review(
        id=uuid.uuid4(),
        user_id=user_id,
        body=body,
        visible=visible,
        work_id=work.id if work else None,
        series_id=series.id if series else None,
    )


# --------------------------------------------------------------------------
# The pools never mix
# --------------------------------------------------------------------------


async def test_a_series_rating_stays_out_of_its_books_average(db_sessionmaker, user):
    async with db_sessionmaker() as db:
        series = await _series(db)
        book = await _work(db, series_id=series.id, series_number=1)
        db.add(_rating(user["id"], 5, series=series))
        db.add(_rating(user["id"], 2, work=book))
        await db.commit()

        book_summary = await review_service.rating_summary(db, book.id)
        series_summary = await review_service.rating_summary(db, series_id=series.id)

    assert book_summary["average"] == 2.0, "the volume keeps its own low mark"
    assert book_summary["count"] == 1
    assert series_summary["average"] == 5.0, "…and the saga keeps its high one"
    assert series_summary["count"] == 1


async def test_a_books_rating_stays_out_of_its_series_average(db_sessionmaker, user):
    """The other direction: five volumes rated 1 must not make the series a 1."""
    async with db_sessionmaker() as db:
        series = await _series(db)
        for i in range(5):
            book = await _work(db, title=f"Volume {i}", series_id=series.id, series_number=i + 1)
            db.add(_rating(user["id"], 1, work=book))
        await db.commit()

        summary = await review_service.rating_summary(db, series_id=series.id)

    assert summary["count"] == 0
    assert summary["average"] is None, "no one has rated the series itself"


async def test_reviews_of_a_series_and_its_book_do_not_appear_on_each_other(
    db_sessionmaker, user
):
    async with db_sessionmaker() as db:
        await _profile(db, user["id"])
        series = await _series(db)
        book = await _work(db, series_id=series.id, series_number=1)
        db.add(_review(user["id"], "A monumental saga.", series=series))
        db.add(_review(user["id"], "This volume drags.", work=book))
        await db.commit()

        on_book = await review_service.public_reviews(db, book.id)
        on_series = await review_service.public_reviews(db, series_id=series.id)

    assert [r["body"] for r in on_book] == ["This volume drags."]
    assert [r["body"] for r in on_series] == ["A monumental saga."]


async def test_the_rating_beside_a_review_is_for_the_same_subject(db_sessionmaker, user):
    """A series review must not be printed next to the reader's rating of a
    book — that would attribute to them a number they never gave the series."""
    async with db_sessionmaker() as db:
        series = await _series(db)
        book = await _work(db, series_id=series.id, series_number=1)
        await _profile(db, user["id"])
        db.add(_rating(user["id"], 1, work=book))  # they disliked the volume
        db.add(_rating(user["id"], 5, series=series))  # …and loved the saga
        db.add(_review(user["id"], "A monumental saga.", series=series))
        db.add(_review(user["id"], "This volume drags.", work=book))
        await db.commit()

        on_series = await review_service.public_reviews(db, series_id=series.id)
        on_book = await review_service.public_reviews(db, book.id)

    assert on_series[0]["rating"] == 5
    assert on_book[0]["rating"] == 1


async def test_a_series_rating_never_touches_the_works_denormalized_average(
    db_sessionmaker, user
):
    """`refresh_aggregate_rating` writes `works.aggregate_rating`; a series
    rating has no work to write to, and must not silently update one."""
    async with db_sessionmaker() as db:
        series = await _series(db)
        book = await _work(db, series_id=series.id, series_number=1)
        db.add(_rating(user["id"], 5, series=series))
        await db.commit()

        await review_service.refresh_aggregate_rating(db, book.id)
        await db.commit()
        await db.refresh(book)

    assert book.aggregate_rating is None


# --------------------------------------------------------------------------
# A row names exactly one subject
# --------------------------------------------------------------------------


@pytest.mark.parametrize("model", [Rating, Review])
async def test_a_row_naming_both_subjects_is_rejected(db_sessionmaker, user, model):
    async with db_sessionmaker() as db:
        series = await _series(db)
        book = await _work(db)
        await db.commit()
        extra = {"value": 4} if model is Rating else {"body": "x"}
        db.add(
            model(id=uuid.uuid4(), user_id=user["id"], work_id=book.id, series_id=series.id, **extra)
        )
        with pytest.raises(IntegrityError):
            await db.commit()


@pytest.mark.parametrize("model", [Rating, Review])
async def test_a_row_naming_no_subject_is_rejected(db_sessionmaker, user, model):
    async with db_sessionmaker() as db:
        extra = {"value": 4} if model is Rating else {"body": "x"}
        db.add(model(id=uuid.uuid4(), user_id=user["id"], **extra))
        with pytest.raises(IntegrityError):
            await db.commit()


# --------------------------------------------------------------------------
# Sync carries them
# --------------------------------------------------------------------------


async def test_sync_pushes_a_series_rating_and_review(client, db_sessionmaker, user):
    async with db_sessionmaker() as db:
        # The pushing reader needs a profile row: every review read inner-joins
        # it, so a review with no profile behind it is invisible to the site.
        await _profile(db, user["id"])
        series = await _series(db)
        await db.commit()
        series_id = str(series.id)

    resp = await client.post(
        "/sync/push",
        json={
            "ops": [
                {
                    "op_id": str(uuid.uuid4()),
                    "device_id": str(uuid.uuid4()),
                    "entity": "ratings",
                    "entity_id": str(uuid.uuid4()),
                    "op_type": "create",
                    "payload": {"id": str(uuid.uuid4()), "series_id": series_id, "value": 5},
                },
                {
                    "op_id": str(uuid.uuid4()),
                    "device_id": str(uuid.uuid4()),
                    "entity": "reviews",
                    "entity_id": str(uuid.uuid4()),
                    "op_type": "create",
                    "payload": {
                        "id": str(uuid.uuid4()),
                        "series_id": series_id,
                        "body": "A monumental saga.",
                        "visible": True,
                    },
                },
            ]
        },
    )
    assert resp.status_code == 200
    assert [r["status"] for r in resp.json()["results"]] == ["applied", "applied"]

    async with db_sessionmaker() as db:
        summary = await review_service.rating_summary(db, series_id=uuid.UUID(series_id))
        reviews = await review_service.public_reviews(db, series_id=uuid.UUID(series_id))
    assert summary["average"] == 5.0
    assert [r["body"] for r in reviews] == ["A monumental saga."]


async def test_a_push_naming_no_subject_fails_that_op_not_the_batch(client):
    """A malformed op must come back as invalid_payload against itself — a raw
    IntegrityError would 500 the whole push and cost the device every queued
    change alongside it."""
    good_id = str(uuid.uuid4())
    resp = await client.post(
        "/sync/push",
        json={
            "ops": [
                {
                    "op_id": str(uuid.uuid4()),
                    "device_id": str(uuid.uuid4()),
                    "entity": "ratings",
                    "entity_id": str(uuid.uuid4()),
                    "op_type": "create",
                    "payload": {"id": str(uuid.uuid4()), "value": 4},
                },
                {
                    "op_id": str(uuid.uuid4()),
                    "device_id": str(uuid.uuid4()),
                    "entity": "personal_tags",
                    "entity_id": good_id,
                    "op_type": "create",
                    "payload": {"id": good_id, "name": "Epics"},
                },
            ]
        },
    )
    assert resp.status_code == 200
    results = resp.json()["results"]
    assert results[0]["status"] == "rejected"
    assert results[0]["code"] == "invalid_payload"
    assert results[1]["status"] == "applied", "the healthy op in the same batch still lands"


# --------------------------------------------------------------------------
# The reader's own profile lists both
# --------------------------------------------------------------------------


async def test_a_readers_profile_lists_their_series_reviews_too(db_sessionmaker, user):
    async with db_sessionmaker() as db:
        await _profile(db, user["id"])
        series = await _series(db)
        book = await _work(db, series_id=series.id, series_number=1)
        db.add(_review(user["id"], "A monumental saga.", series=series))
        db.add(_review(user["id"], "This volume drags.", work=book))
        await db.commit()

        rows = await review_service.reader_reviews(db, user["id"])

    bodies = {r["body"] for r in rows}
    assert bodies == {"A monumental saga.", "This volume drags."}
    series_row = next(r for r in rows if r["series"] is not None)
    assert series_row["work"] is None
    assert series_row["series"].name == "Ponniyin Selvan"
