"""Fold three spellings of one publisher, then read a cover under each of them.

The console can now merge N rows from a list (admin/console/templates/
_bulk_merge.html), which is what "merge every DC Books into one" actually needs
— Keep/Absorb could only ever pair two. The half that matters afterwards is the
one the owner has asked for twice: **once a record is merged, a scan must land
on the survivor**, not re-create the row that was folded away.

That resolution lives in `catalog_service`, and this exercises it end to end
through the same functions the cover extractor and the ISBN cache call — the
console's own bulk-merge endpoint is thin glue over `merge_service.merge`, so
what is worth pinning is that the glue leaves the catalogue in a state these
paths read correctly.
"""

import uuid

import pytest
from sqlalchemy import select

from app.models import Edition, Publisher, Work
from app.services import catalog_service, merge_service

# The three spellings from the owner's Publishers search, 5 Sep 2026.
SPELLINGS = ["DC Books", "Ḍi Si Buks", "ഡിസി ബുക്സ്"]


async def _publisher(db, name: str, *, editions: int = 0) -> Publisher:
    publisher = await catalog_service._get_or_create(db, Publisher, name)
    await db.flush()
    for _ in range(editions):
        work = Work(title=f"Book for {name}")
        db.add(work)
        await db.flush()
        db.add(Edition(work_id=work.id, publisher_id=publisher.id))
    await db.commit()
    return publisher


async def _fold_all_into_first(db, rows: list[Publisher]) -> Publisher:
    """What the console's bulk-merge endpoint does: one survivor, N losers."""
    survivor, *losers = rows
    for loser in losers:
        assert await merge_service.merge(db, "publishers", survivor.id, loser.id)
    await db.commit()
    return survivor


async def test_every_folded_spelling_resolves_to_the_survivor(db_sessionmaker):
    async with db_sessionmaker() as db:
        rows = [
            await _publisher(db, SPELLINGS[0], editions=4),
            await _publisher(db, SPELLINGS[1], editions=1),
            await _publisher(db, SPELLINGS[2], editions=2),
        ]
        survivor = await _fold_all_into_first(db, rows)
        survivor_id = survivor.id

    # A cover read under ANY of the three names — including the two that no
    # longer exist as live rows — lands on the one house.
    async with db_sessionmaker() as db:
        for name in SPELLINGS:
            resolved = await catalog_service._resolve_publisher(db, None, name)
            assert resolved is not None, name
            assert resolved.id == survivor_id, f"{name} resolved away from the survivor"


async def test_a_folded_spelling_is_not_re_created(db_sessionmaker):
    """The failure this prevents: the extractor reads “ഡിസി ബുക്സ്”, finds no live
    row spelled that way, and makes a fourth one — undoing the merge silently."""
    async with db_sessionmaker() as db:
        rows = [
            await _publisher(db, SPELLINGS[0], editions=4),
            await _publisher(db, SPELLINGS[2], editions=2),
        ]
        await _fold_all_into_first(db, rows)

    async with db_sessionmaker() as db:
        await catalog_service._resolve_publisher(db, None, SPELLINGS[2])
        await db.commit()

    async with db_sessionmaker() as db:
        live = (
            (
                await db.execute(
                    select(Publisher).where(
                        Publisher.name == SPELLINGS[2],
                        Publisher.deleted_at.is_(None),
                    )
                )
            )
            .scalars()
            .all()
        )
        assert live == [], "the folded spelling came back as a new row"


async def test_a_remembered_id_from_before_the_merge_still_lands_right(db_sessionmaker):
    """An app install that has not searched since the merge still holds the old
    id — in a cached row, or a form left open."""
    async with db_sessionmaker() as db:
        rows = [
            await _publisher(db, SPELLINGS[0], editions=4),
            await _publisher(db, SPELLINGS[1], editions=1),
        ]
        stale_id = rows[1].id
        survivor = await _fold_all_into_first(db, rows)
        survivor_id = survivor.id

    async with db_sessionmaker() as db:
        resolved = await catalog_service._resolve_publisher(db, stale_id, None)
        assert resolved is not None
        assert resolved.id == survivor_id


async def test_folding_a_row_others_point_at_keeps_the_graph_flat(db_sessionmaker):
    """Resolution does a single hop, so a chain silently dead-ends. Merging in
    two goes — as an operator working a list does — must not build one."""
    async with db_sessionmaker() as db:
        a = await _publisher(db, SPELLINGS[0], editions=4)
        b = await _publisher(db, SPELLINGS[1], editions=1)
        c = await _publisher(db, SPELLINGS[2], editions=2)
        # c → b first, then b → a.
        assert await merge_service.merge(db, "publishers", b.id, c.id)
        await db.commit()
        assert await merge_service.merge(db, "publishers", a.id, b.id)
        await db.commit()
        a_id, c_id = a.id, c.id

    async with db_sessionmaker() as db:
        far = await db.get(Publisher, c_id)
        assert far.merged_into_id == a_id, "the far end must point straight at the survivor"
        resolved = await catalog_service._resolve_publisher(db, None, SPELLINGS[2])
        assert resolved.id == a_id


@pytest.mark.parametrize("kind", ["authors", "publishers", "series"])
def test_every_name_kind_the_console_offers_has_an_engine(kind):
    """The list component is shared by four screens; three of them route here,
    and a kind the console offers with no engine behind it would 500 on submit."""
    assert kind in merge_service.MODELS


async def test_an_unmerge_puts_the_spelling_back(db_sessionmaker):
    """The reassurance the merge panel prints before you press anything."""
    async with db_sessionmaker() as db:
        rows = [
            await _publisher(db, SPELLINGS[0], editions=4),
            await _publisher(db, SPELLINGS[1], editions=1),
        ]
        loser_id = rows[1].id
        await _fold_all_into_first(db, rows)

    async with db_sessionmaker() as db:
        assert await merge_service.unmerge(db, "publishers", loser_id)
        await db.commit()

    async with db_sessionmaker() as db:
        back = await db.get(Publisher, loser_id)
        assert back.merged_into_id is None
        assert back.deleted_at is None
        resolved = await catalog_service._resolve_publisher(db, None, SPELLINGS[1])
        assert resolved.id == loser_id


async def test_merging_into_itself_is_refused(db_sessionmaker):
    async with db_sessionmaker() as db:
        only = await _publisher(db, SPELLINGS[0], editions=1)
        assert not await merge_service.merge(db, "publishers", only.id, only.id)


async def test_a_publisher_nobody_merged_is_untouched(db_sessionmaker):
    """A different house that merely shares the search — Ḍi. Vi. Ke. Mūrti sat in
    the same result list and must survive the operator's selection untouched."""
    async with db_sessionmaker() as db:
        rows = [
            await _publisher(db, SPELLINGS[0], editions=4),
            await _publisher(db, SPELLINGS[1], editions=1),
        ]
        other = await _publisher(db, "Ḍi. Vi. Ke. Mūrti", editions=3)
        other_id = other.id
        await _fold_all_into_first(db, rows)

    async with db_sessionmaker() as db:
        untouched = await db.get(Publisher, other_id)
        assert untouched.merged_into_id is None
        assert untouched.deleted_at is None
        resolved = await catalog_service._resolve_publisher(db, None, "Ḍi. Vi. Ke. Mūrti")
        assert resolved.id == other_id


async def test_the_survivor_keeps_every_edition(db_sessionmaker):
    async with db_sessionmaker() as db:
        rows = [
            await _publisher(db, SPELLINGS[0], editions=4),
            await _publisher(db, SPELLINGS[1], editions=1),
            await _publisher(db, SPELLINGS[2], editions=2),
        ]
        survivor = await _fold_all_into_first(db, rows)
        survivor_id = survivor.id

    async with db_sessionmaker() as db:
        n = len(
            (await db.execute(select(Edition).where(Edition.publisher_id == survivor_id)))
            .scalars()
            .all()
        )
        assert n == 7, "an edition was left behind on a folded row"
        assert uuid.UUID(str(survivor_id))
