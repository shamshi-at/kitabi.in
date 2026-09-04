"""A merge decided once is honoured everywhere a name comes back.

"ഡി സി ബുക്സ്" and "DC Books" are one house, and an admin has said so in the
console. Nothing else can know it: the two spellings share neither letters nor
script, so no fold, no transliteration and no trigram will ever put them
together — the pointer that merge left behind is the only evidence there is.

So every path that turns a free-text name (or a remembered id) back into a
catalogue row has to follow it. Otherwise the merge holds exactly until the
next Malayalam cover is photographed: the extractor reads the loser's spelling,
the form offers it back, and the duplicate reopens next door.
"""

import uuid

from sqlalchemy import func, select

from app.models import Author, Edition, Publisher, Series, Work
from app.services import catalog_service, merge_service

MALAYALAM = "ഡി സി ബുക്സ്"


async def _publisher(db, name, *, editions=0):
    row = Publisher(name=name)
    db.add(row)
    await db.flush()
    for i in range(editions):
        work = Work(title=f"{name} book {i}")
        db.add(work)
        await db.flush()
        db.add(Edition(work_id=work.id, publisher_id=row.id))
    await db.flush()
    return row


async def _merged_publishers(db, *, survivor_name="DC Books", loser_name=MALAYALAM):
    """The state after an admin merges the Malayalam spelling into the English
    one — through the real merge, not by hand-setting the columns."""
    survivor = await _publisher(db, survivor_name, editions=4)
    loser = await _publisher(db, loser_name, editions=1)
    assert await merge_service.merge(db, "publishers", survivor.id, loser.id)
    await db.commit()
    return survivor, loser


def _extraction(monkeypatch, fields):
    """Arm the cover extractor to return [fields] without a key or a photo."""
    from app.core.config import get_settings
    from app.services import extraction_service

    settings = get_settings()
    monkeypatch.setattr(type(settings), "extraction_enabled", property(lambda _: True))
    monkeypatch.setattr(extraction_service, "allowed_image_url", lambda *_a, **_kw: True)

    async def _fake(*_args, **_kwargs):
        return {
            "title": None,
            "authors": [],
            "publisher": None,
            "description": None,
            "series_name": None,
            "series_number": None,
            "language": None,
            "form": None,
            "isbn": None,
            **fields,
        }

    monkeypatch.setattr(extraction_service, "extract_from_covers", _fake)


async def _extract(client):
    resp = await client.post(
        "/catalog/cover-extract", json={"front_url": "https://example.test/front.jpg"}
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


# --- what a scanned cover suggests ---------------------------------------


async def test_a_merged_publisher_spelling_suggests_the_survivor(
    client, db_sessionmaker, monkeypatch
):
    """The reported case (4 Sep 2026). The cover prints the Malayalam name; the
    catalogue keeps that house as "DC Books"; the form must say DC Books."""
    async with db_sessionmaker() as db:
        survivor, _ = await _merged_publishers(db)
        survivor_id, survivor_name = str(survivor.id), survivor.name

    _extraction(monkeypatch, {"title": "Meerasadhu", "publisher": MALAYALAM})
    body = await _extract(client)

    assert body["publisher"] == survivor_name
    assert body["publisher_id"] == survivor_id


async def test_a_merged_author_spelling_suggests_the_survivor(client, db_sessionmaker, monkeypatch):
    async with db_sessionmaker() as db:
        survivor = Author(name="Vaikom Muhammad Basheer")
        loser = Author(name="ബഷീർ")
        db.add_all([survivor, loser])
        await db.flush()
        assert await merge_service.merge(db, "authors", survivor.id, loser.id)
        await db.commit()
        survivor_name = survivor.name

    _extraction(monkeypatch, {"title": "Balyakalasakhi", "authors": ["ബഷീർ"]})
    body = await _extract(client)

    assert body["authors"] == [survivor_name]


async def test_a_merged_series_spelling_suggests_the_survivor(client, db_sessionmaker, monkeypatch):
    async with db_sessionmaker() as db:
        survivor = Series(name="Aithihyamala")
        loser = Series(name="ഐതിഹ്യമാല")
        db.add_all([survivor, loser])
        await db.flush()
        assert await merge_service.merge(db, "series", survivor.id, loser.id)
        await db.commit()
        survivor_name = survivor.name

    _extraction(monkeypatch, {"title": "Kottarathil Sankunni", "series_name": "ഐതിഹ്യമാല"})
    body = await _extract(client)

    assert body["series_name"] == survivor_name


async def test_a_name_the_catalogue_has_never_seen_comes_back_verbatim(
    client, db_sessionmaker, monkeypatch
):
    """Canonicalising is exact-name-or-merge-pointer only. A house nobody has
    catalogued must reach the form as the cover prints it — a suggestion that
    quietly swaps in a near-miss is worse than the book's own words."""
    async with db_sessionmaker() as db:
        await _publisher(db, "DC Books", editions=3)
        await db.commit()

    _extraction(monkeypatch, {"publisher": "Nobody Press", "authors": ["A Stranger"]})
    body = await _extract(client)

    assert body["publisher"] == "Nobody Press"
    assert body["publisher_id"] is None
    assert body["authors"] == ["A Stranger"]


# --- what the pickers offer ----------------------------------------------


# The names below are deliberately ones no matcher could bridge on its own.
# "ഡി സി ബുക്സ്" romanizes to "di si buks", which the fuzzy search already
# reaches "DC Books" with — a pair like that proves nothing about the pointer.
# An initialism and a pen name have no letters in common with what they name,
# so a hit can only have come from the merge a human recorded.
NBS = "എൻ ബി എസ്"  # romanizes to "en bi es" — nothing like "National Book Stall"


async def test_the_publisher_typeahead_answers_a_merged_spelling(client, db_sessionmaker):
    """Filtering the loser out is only half the decision: it stops the dead row
    being shown and leaves the reader who spells the house their way with an
    empty list, whose one obvious next move is to create it again."""
    async with db_sessionmaker() as db:
        survivor = await _publisher(db, "National Book Stall", editions=4)
        loser = await _publisher(db, NBS, editions=1)
        assert await merge_service.merge(db, "publishers", survivor.id, loser.id)
        await db.commit()
        survivor_id, loser_id = str(survivor.id), str(loser.id)

    resp = await client.get("/catalog/publishers", params={"q": NBS})
    assert resp.status_code == 200
    ids = [row["id"] for row in resp.json()]

    assert ids == [survivor_id]
    assert loser_id not in ids


async def test_the_author_typeahead_answers_a_merged_spelling(client, db_sessionmaker):
    """A pen name is the same fact about people: nothing in "Beypore Sultan"
    spells "Vaikom Muhammad Basheer" — only the merge knows."""
    async with db_sessionmaker() as db:
        survivor = Author(name="Vaikom Muhammad Basheer")
        loser = Author(name="Beypore Sultan")
        db.add_all([survivor, loser])
        await db.flush()
        assert await merge_service.merge(db, "authors", survivor.id, loser.id)
        await db.commit()
        survivor_id, loser_id = str(survivor.id), str(loser.id)

    resp = await client.get("/catalog/authors", params={"q": "Beypore Sultan"})
    assert resp.status_code == 200
    ids = [row["id"] for row in resp.json()]

    assert ids == [survivor_id]
    assert loser_id not in ids


async def test_several_losers_collapse_to_one_row(client, db_sessionmaker):
    """Three spellings of one house must not offer that house three times."""
    async with db_sessionmaker() as db:
        survivor = await _publisher(db, "DC Books", editions=5)
        for name in ("DC books", "D C Books", "Dc Books"):
            loser = await _publisher(db, name)
            assert await merge_service.merge(db, "publishers", survivor.id, loser.id)
        await db.commit()
        survivor_id = str(survivor.id)

    resp = await client.get("/catalog/publishers", params={"q": "DC Books"})
    ids = [row["id"] for row in resp.json()]

    assert ids.count(survivor_id) == 1
    assert ids == [survivor_id]


# --- what a save lands on -------------------------------------------------


async def test_adding_a_publisher_by_a_merged_name_reuses_the_survivor(client, db_sessionmaker):
    """The picker's "add new" is the other way a name becomes a row."""
    async with db_sessionmaker() as db:
        survivor, _ = await _merged_publishers(db)
        survivor_id = str(survivor.id)

    resp = await client.post("/catalog/publishers", json={"name": MALAYALAM})
    assert resp.status_code == 201
    assert resp.json()["id"] == survivor_id

    async with db_sessionmaker() as db:
        total = await db.scalar(select(func.count()).select_from(Publisher))
    assert total == 2, "a third row means the merge was undone by the next save"


async def test_a_remembered_publisher_id_lands_on_the_survivor(client, db_sessionmaker):
    """An id can be older than the merge — a form left open, an install that
    hasn't searched since. It must still land on the house that was kept."""
    async with db_sessionmaker() as db:
        survivor, loser = await _merged_publishers(db)
        survivor_id, loser_id = str(survivor.id), str(loser.id)

    resp = await client.post(
        "/catalog/works", json={"title": "Meerasadhu", "publisher_id": loser_id}
    )
    assert resp.status_code == 201
    assert resp.json()["editions"][0]["publisher"]["id"] == survivor_id


async def test_a_remembered_author_id_lands_on_the_survivor(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        survivor = Author(name="Vaikom Muhammad Basheer")
        loser = Author(name="ബഷീർ")
        db.add_all([survivor, loser])
        await db.flush()
        assert await merge_service.merge(db, "authors", survivor.id, loser.id)
        await db.commit()
        survivor_id, loser_id = str(survivor.id), str(loser.id)

    resp = await client.post(
        "/catalog/works", json={"title": "Balyakalasakhi", "author_ids": [loser_id]}
    )
    assert resp.status_code == 201
    assert [a["id"] for a in resp.json()["authors"]] == [survivor_id]


async def test_a_merged_name_typed_into_the_form_lands_on_the_survivor(client, db_sessionmaker):
    """The free-text path — CSV import, OpenLibrary cache, a typed name."""
    async with db_sessionmaker() as db:
        survivor, _ = await _merged_publishers(db)
        survivor_id = str(survivor.id)

    resp = await client.post(
        "/catalog/works", json={"title": "Meerasadhu", "publisher_name": MALAYALAM}
    )
    assert resp.status_code == 201
    assert resp.json()["editions"][0]["publisher"]["id"] == survivor_id


# --- the rule itself ------------------------------------------------------


async def test_canonical_reads_a_dead_end_as_no_answer(db_sessionmaker):
    """Soft-deleted without a merge points nowhere, and so does a pointer whose
    survivor has since gone. Both mean the caller holds a name that no longer
    names anything."""
    async with db_sessionmaker() as db:
        live = await _publisher(db, "Green Books")
        orphan = await _publisher(db, "Gone Press")
        orphan.deleted_at = catalog_service.datetime.now(catalog_service.UTC)
        await db.commit()

        assert await merge_service.canonical(db, live) is live
        assert await merge_service.canonical(db, orphan) is None
        assert await merge_service.canonical(db, None) is None
        assert await catalog_service.publisher_by_name(db, "Gone Press") is None
        assert (
            await catalog_service.canonical_name(db, Publisher, "Gone Press") == "Gone Press"
        ), "an unusable row must not rename what the cover printed"


async def test_a_merged_pointer_survives_the_survivor_being_renamed(client, db_sessionmaker):
    """The pointer names a row, not a spelling — renaming the survivor moves
    every merged name with it."""
    async with db_sessionmaker() as db:
        survivor, _ = await _merged_publishers(db)
        survivor.name = "DC Books Kottayam"
        await db.commit()
        survivor_id = str(survivor.id)

    async with db_sessionmaker() as db:
        picked = await catalog_service.publisher_by_name(db, MALAYALAM)

    assert picked is not None
    assert str(picked.id) == survivor_id
    assert picked.name == "DC Books Kottayam"
    assert uuid.UUID(survivor_id)
