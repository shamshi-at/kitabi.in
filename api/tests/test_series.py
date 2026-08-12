"""Series as a real entity: picked rather than typed, one ordering shared by
every translation, and a page that shows a position once.

The rule under test throughout: **a position in a series belongs to the story.**
It cannot differ between two printings of the same book (which is why it moved
off Edition), and it is the same in every language the book exists in (which is
why a translation inherits it instead of starting a parallel series).
"""

import uuid

import pytest

from app.models import Author, Series, Work
from app.services import catalog_service, merge_service, public_service, slug_service


async def _series(db, name: str, **kw) -> Series:
    row = Series(name=name, **kw)
    db.add(row)
    await db.flush()
    await slug_service.ensure_slug(db, row)
    return row


async def _work(db, title: str, *, series=None, number=None, language=None, **kw) -> Work:
    row = Work(
        title=title,
        series_id=series.id if series else None,
        series_number=number,
        language=language,
        **kw,
    )
    db.add(row)
    await db.flush()
    await slug_service.ensure_slug(db, row)
    return row


# --------------------------------------------------------------------------
# Picking a series instead of typing one
# --------------------------------------------------------------------------


async def test_a_work_is_created_into_a_picked_series(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        series = await _series(db, "Malgudi")
        await db.commit()
        series_id = str(series.id)

    resp = await client.post(
        "/catalog/works",
        json={"title": "Swami and Friends", "series_id": series_id, "series_number": 1},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["series"]["name"] == "Malgudi"
    assert body["series_number"] == 1
    # …and the edition still carries it, because installs in the field read it
    # there (it lived on the edition until migration 000043).
    assert body["editions"][0]["series"]["name"] == "Malgudi"
    assert body["editions"][0]["series_number"] == 1


async def test_a_typed_series_still_works_for_import_and_extraction(client):
    """The CSV import and the cover extractor only ever have a string."""
    resp = await client.post(
        "/catalog/works", json={"title": "Ponniyin Selvan 1", "series_name": "Ponniyin Selvan"}
    )
    assert resp.status_code == 201
    assert resp.json()["series"]["name"] == "Ponniyin Selvan"


async def test_a_picked_series_beats_a_typed_one(client, db_sessionmaker):
    """Both arriving at once is the shape of a stale form: the id is the one
    the reader chose from a list, the name is whatever was in the box."""
    async with db_sessionmaker() as db:
        series = await _series(db, "Malgudi")
        await db.commit()
        series_id = str(series.id)

    resp = await client.post(
        "/catalog/works",
        json={"title": "The Bachelor of Arts", "series_id": series_id, "series_name": "Malgudy"},
    )
    assert resp.json()["series"]["name"] == "Malgudi"


async def test_series_search_is_cross_script(client, db_sessionmaker):
    """The reason the free-text field kept splitting one ordering in two: a
    Malayalam name was invisible to a Latin query, so the reader typed a new
    one beside it."""
    async with db_sessionmaker() as db:
        await _series(db, "ഐതിഹ്യമാല")
        await db.commit()

    resp = await client.get("/catalog/search/series", params={"q": "aithihyamala"})
    assert resp.status_code == 200
    assert [s["name"] for s in resp.json()] == ["ഐതിഹ്യമാല"]


async def test_browse_series_counts_the_books(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        held = await _series(db, "Malgudi")
        await _series(db, "Empty Row From A Typo")
        await _work(db, "Swami and Friends", series=held, number=1)
        await _work(db, "The Bachelor of Arts", series=held, number=2)
        await db.commit()

    resp = await client.get("/catalog/browse/series", params={"sort": "popular"})
    rows = resp.json()
    assert rows[0]["name"] == "Malgudi"
    assert rows[0]["book_count"] == 2
    assert rows[-1]["book_count"] == 0  # the typo, visible as empty rather than hidden


async def test_creating_a_series_is_idempotent_on_name(client):
    first = await client.post("/catalog/series", json={"name": "Malgudi"})
    second = await client.post("/catalog/series", json={"name": "malgudi"})
    assert first.status_code == 201
    assert second.json()["id"] == first.json()["id"]


# --------------------------------------------------------------------------
# Filtering and ordering
# --------------------------------------------------------------------------


async def test_browse_filters_by_series_in_reading_order(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        series = await _series(db, "Malgudi")
        other = await _series(db, "Elsewhere")
        await _work(db, "Third", series=series, number=3)
        await _work(db, "First", series=series, number=1)
        await _work(db, "Unnumbered", series=series)
        await _work(db, "Not in it", series=other, number=1)
        await db.commit()
        series_id = str(series.id)

    resp = await client.get("/catalog/browse/works", params={"series": series_id, "sort": "series"})
    titles = [w["title"] for w in resp.json()]
    assert titles == ["First", "Third", "Unnumbered"]  # unnumbered sorts last, not first


async def test_a_series_page_lists_its_books_in_order(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        series = await _series(db, "Malgudi")
        await _work(db, "Second", series=series, number=2)
        await _work(db, "First", series=series, number=1)
        await db.commit()
        series_id = str(series.id)

    resp = await client.get(f"/catalog/series/{series_id}/works")
    assert [w["title"] for w in resp.json()] == ["First", "Second"]


# --------------------------------------------------------------------------
# Translations share the position
# --------------------------------------------------------------------------


async def test_a_translation_inherits_the_position_at_create_time(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        series = await _series(db, "Ponniyin Selvan", primary_language="Tamil")
        original = await _work(db, "First Flood", series=series, number=1, language="Tamil")
        await db.commit()
        original_id = str(original.id)

    resp = await client.post(
        "/catalog/works",
        json={
            "title": "ആദ്യത്തെ വെള്ളപ്പൊക്കം",
            "language": "Malayalam",
            "original_work_id": original_id,
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["series"]["name"] == "Ponniyin Selvan"
    assert body["series_number"] == 1, "book 1 is book 1 in every language"


async def test_linking_a_translation_afterwards_shares_the_position(db_sessionmaker):
    async with db_sessionmaker() as db:
        series = await _series(db, "Ponniyin Selvan")
        original = await _work(db, "First Flood", series=series, number=1, language="Tamil")
        translation = await _work(db, "Adyathe Vellappokkam", language="Malayalam")
        await db.commit()
        await catalog_service.link_translation(db, translation, original, relation="original")
        await db.refresh(translation)

        assert translation.series_id == series.id
        assert translation.series_number == 1


async def test_setting_a_series_reaches_the_whole_group(db_sessionmaker):
    """Catalogue the series on whichever language you happen to be holding."""
    async with db_sessionmaker() as db:
        series = await _series(db, "Ponniyin Selvan")
        original = await _work(db, "First Flood", language="Tamil")
        translation = await _work(db, "Adyathe Vellappokkam", language="Malayalam")
        await catalog_service.link_translation(db, translation, original, relation="original")

        await catalog_service.set_work_series(db, original, series, 1)
        await db.commit()
        await db.refresh(translation)

    assert translation.series_id == series.id
    assert translation.series_number == 1


async def test_a_translation_in_its_own_local_series_is_left_alone(db_sessionmaker):
    """A publisher who bundles a translation into their own local series has
    made a real editorial decision; inheritance must not overwrite it."""
    async with db_sessionmaker() as db:
        original_series = await _series(db, "Discworld")
        local_series = await _series(db, "മലയാളം ഫാന്റസി പരമ്പര")
        original = await _work(db, "Mort", series=original_series, number=4, language="English")
        translation = await _work(db, "മോർട്ട്", series=local_series, number=2, language="Malayalam")
        await db.commit()
        await catalog_service.link_translation(db, translation, original, relation="original")
        await db.refresh(translation)

    assert translation.series_id == local_series.id
    assert translation.series_number == 2


# --------------------------------------------------------------------------
# The public series page
# --------------------------------------------------------------------------


async def test_the_public_page_shows_a_position_once(db_sessionmaker):
    """The whole point of the design: three languages of book 1 are one entry
    on the page, not three."""
    async with db_sessionmaker() as db:
        series = await _series(db, "Ponniyin Selvan", primary_language="Tamil")
        group = uuid.uuid4()
        original = await _work(
            db,
            "First Flood",
            series=series,
            number=1,
            language="Tamil",
            translation_group_id=group,
        )
        for title, language in (("Adyathe Vellappokkam", "Malayalam"), ("First Flood EN", "En")):
            row = await _work(
                db, title, series=series, number=1, language=language, translation_group_id=group
            )
            row.original_work_id = original.id
        await _work(db, "Whirlwind", series=series, number=2, language="Tamil")
        await db.commit()
        slug = series.slug

        page = await public_service.series_page(db, slug)

    assert [e.number for e in page.entries] == [1, 2]
    first = page.entries[0]
    assert first.book.title == "First Flood", "the original represents the position"
    assert sorted(c.language for c in first.also) == ["En", "Malayalam"]
    # The flat list is still served for the renderer deployed before entries.
    assert len(page.works) == 4
    assert page.languages == ["En", "Malayalam", "Tamil"]


async def test_a_one_book_series_in_three_languages_is_not_indexable(db_sessionmaker):
    """Two works is not two books when both are the same story — indexing that
    as a series is exactly the thin page the rule exists to prevent."""
    async with db_sessionmaker() as db:
        series = await _series(db, "Solo")
        group = uuid.uuid4()
        for title in ("Only Book", "Only Book (ml)"):
            await _work(db, title, series=series, number=1, translation_group_id=group)
        await db.commit()
        page = await public_service.series_page(db, series.slug)

    assert len(page.works) == 2
    assert len(page.entries) == 1
    assert page.indexable is False


# --------------------------------------------------------------------------
# Duplicates
# --------------------------------------------------------------------------


async def test_duplicate_series_merge_and_keep_the_books(db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _series(db, "Malgudi")
        drop = await _series(db, "malgudi ")
        await _work(db, "Swami and Friends", series=keep, number=1)
        await _work(db, "The Bachelor of Arts", series=drop, number=2)
        await db.commit()

        assert await merge_service.merge(db, "series", keep.id, drop.id)
        await db.commit()

        works = await catalog_service.series_works(db, keep.id)
        assert [w.title for w in works] == ["Swami and Friends", "The Bachelor of Arts"]
        assert [w.series_number for w in works] == [1, 2], "positions survive a merge"
        await db.refresh(drop)
        assert drop.merged_into_id == keep.id


async def test_a_stale_id_for_a_merged_series_lands_on_the_survivor(client, db_sessionmaker):
    """An app install can hold the losing id for as long as it likes."""
    async with db_sessionmaker() as db:
        keep = await _series(db, "Malgudi")
        drop = await _series(db, "malgudi ")
        await db.commit()
        assert await merge_service.merge(db, "series", keep.id, drop.id)
        await db.commit()
        stale_id = str(drop.id)

    resp = await client.post(
        "/catalog/works", json={"title": "Waiting for the Mahatma", "series_id": stale_id}
    )
    assert resp.status_code == 201
    assert resp.json()["series"]["name"] == "Malgudi"


@pytest.mark.parametrize("kind", ["authors", "publishers", "series"])
def test_every_mergeable_kind_has_a_carry_over_list(kind):
    """A kind in MODELS without one silently drops fields on every merge."""
    assert kind in merge_service.MODELS
    assert merge_service._CARRY_OVER[kind]


# --------------------------------------------------------------------------
# The old shape keeps working
# --------------------------------------------------------------------------


async def test_an_edition_patch_still_sets_the_series(client, db_sessionmaker):
    """App installs that predate the move send series on the edition."""
    async with db_sessionmaker() as db:
        author = Author(name="R. K. Narayan")
        db.add(author)
        await db.flush()
        work = await _work(db, "The Guide")
        await db.commit()
        work_id = str(work.id)

    resp = await client.post(
        f"/catalog/works/{work_id}/editions", json={"series_name": "Malgudi", "series_number": 7}
    )
    assert resp.status_code == 201

    resp = await client.get(f"/catalog/works/{work_id}")
    body = resp.json()
    assert body["series"]["name"] == "Malgudi", "it landed on the work, not just the edition"
    assert body["series_number"] == 7
