"""Which publisher row a free-text name lands on.

A publisher name almost never arrives from the picker — it is read off a
photographed cover, imported from OpenLibrary, or typed. The catalogue holds
near-duplicate publisher rows (merging them is a manual admin job), so the
question "which DC Books?" has to have a deterministic, useful answer: the one
the rest of the shelf already uses.
"""

import uuid

from app.models import Edition, Publisher, Work
from app.services import catalog_service


async def _publisher(db, name, *, editions=0, **kw):
    p = Publisher(name=name, **kw)
    db.add(p)
    await db.flush()
    for i in range(editions):
        work = Work(title=f"{name} book {i}")
        db.add(work)
        await db.flush()
        db.add(Edition(work_id=work.id, publisher_id=p.id))
    await db.flush()
    return p


async def test_duplicate_names_resolve_to_the_most_used_row(db_sessionmaker):
    """Two rows spelled the same: the one carrying the books wins."""
    async with db_sessionmaker() as db:
        empty = await _publisher(db, "DC Books")
        busy = await _publisher(db, "DC Books", editions=3)
        await db.commit()

        picked = await catalog_service.publisher_by_name(db, "DC Books")

    assert picked is not None
    assert picked.id == busy.id
    assert picked.id != empty.id


async def test_duplicate_names_do_not_blow_up_the_save(client, db_sessionmaker):
    """The old lookup was `scalar_one_or_none()`, which *raises* the moment two
    rows share a name — so a cover that read "DC Books" 500'd the whole add."""
    async with db_sessionmaker() as db:
        await _publisher(db, "DC Books")
        busy = await _publisher(db, "DC Books", editions=2)
        await db.commit()
        busy_id = str(busy.id)

    resp = await client.post(
        "/catalog/works",
        json={"title": "Meerasadhu", "publisher_name": "DC Books"},
    )
    assert resp.status_code == 201
    assert resp.json()["editions"][0]["publisher"]["id"] == busy_id


async def test_exact_spelling_beats_a_busier_fold_neighbour(db_sessionmaker):
    """The fold tier collapses spellings of one house, but it must never
    outrank the spelling actually printed on the cover."""
    async with db_sessionmaker() as db:
        await _publisher(db, "Mathrubhoomi Books", editions=9)
        exact = await _publisher(db, "Mathrubhumi Books", editions=1)
        await db.commit()

        picked = await catalog_service.publisher_by_name(db, "Mathrubhumi Books")

    assert picked is not None
    assert picked.id == exact.id


async def test_a_spelling_variant_reuses_the_existing_house(db_sessionmaker):
    """No exact row, but one whose romanized skeleton matches — reuse it rather
    than open a second house next door."""
    async with db_sessionmaker() as db:
        existing = await _publisher(db, "Mathrubhoomi Books", editions=4)
        await db.commit()

        picked = await catalog_service.publisher_by_name(db, "Mathrubhumi Books")

    assert picked is not None
    assert picked.id == existing.id


async def test_a_merged_away_name_resolves_to_its_survivor(db_sessionmaker):
    """Merging soft-deletes the loser. Without following the pointer, the next
    cover that reads the loser's name re-creates the duplicate an admin had
    just merged away."""
    async with db_sessionmaker() as db:
        survivor = await _publisher(db, "Green Books", editions=5)
        loser = await _publisher(db, "Green Bookss")
        loser.merged_into_id = survivor.id
        loser.deleted_at = catalog_service.datetime.now(catalog_service.UTC)
        await db.commit()

        picked = await catalog_service.publisher_by_name(db, "Green Bookss")
        resolved = await catalog_service._get_or_create(db, Publisher, "Green Bookss")

    # Fold catches the doubled 's' before the merge pointer is even needed…
    assert picked is not None
    assert picked.id == survivor.id
    # …and the plain get-or-create follows the merge rather than inserting.
    assert resolved.id == survivor.id


async def test_an_unknown_house_is_still_created(db_sessionmaker):
    async with db_sessionmaker() as db:
        assert await catalog_service.publisher_by_name(db, "Nobody Press") is None
        created = await catalog_service._get_or_create(db, Publisher, "Nobody Press")
        await db.commit()

    assert isinstance(created, Publisher)
    assert created.name == "Nobody Press"
    assert created.slug


async def test_cover_extract_returns_the_canonical_publisher(client, db_sessionmaker, monkeypatch):
    """The form should show — and save against — the house the rest of the
    shelf uses, not the spelling this one cover happens to print."""
    from app.core.config import get_settings
    from app.services import extraction_service

    async with db_sessionmaker() as db:
        await _publisher(db, "DC Books")
        busy = await _publisher(db, "DC Books", editions=6)
        await db.commit()
        busy_id, busy_name = str(busy.id), busy.name

    settings = get_settings()
    monkeypatch.setattr(type(settings), "extraction_enabled", property(lambda _: True))
    monkeypatch.setattr(
        extraction_service,
        "allowed_image_url",
        lambda *_args, **_kw: True,
    )

    async def _fake_extract(*_args, **_kwargs):
        return {"title": "Meerasadhu", "publisher": "dc books"}

    monkeypatch.setattr(extraction_service, "extract_from_covers", _fake_extract)

    resp = await client.post(
        "/catalog/cover-extract",
        json={"front_url": "https://example.test/front.jpg"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["publisher"] == busy_name
    assert body["publisher_id"] == busy_id
    assert uuid.UUID(body["publisher_id"])
