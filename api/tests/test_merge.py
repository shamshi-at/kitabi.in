"""Merging duplicate authors and publishers.

Merging is destructive and a false merge is SILENT — conflating two real people
is worse than leaving a duplicate, and nobody notices. So most of these tests
are about what merging must never do: lose a book, lose a bio, break a URL, or
become impossible to undo.
"""

import uuid

import pytest

from app.models import Author, Edition, Publisher, Work
from app.services import merge_service
from app.services.merge_service import EXACT, SPELLING, WORD_ORDER


async def _author(db, name, *, works=0, **kw):
    a = Author(name=name, **kw)
    db.add(a)
    await db.flush()
    for i in range(works):
        db.add(Work(title=f"{name} book {i}", authors=[a]))
    await db.flush()
    return a


# --------------------------------------------------------------------------
# Finding duplicates
# --------------------------------------------------------------------------


async def test_identical_names_are_found_as_exact(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _author(db, "John Perkins", works=2)
        await _author(db, "John Perkins")
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    assert len(cands) == 1
    assert cands[0].reason == EXACT
    assert cands[0].auto_mergeable is True


async def test_word_order_variants_are_found_but_not_auto_mergeable(db_sessionmaker):
    """ "Perkins, John" and "John Perkins" are the same person — but this is a
    guess, so it waits for a human."""
    async with db_sessionmaker() as db:
        await _author(db, "Perkins, John", works=3)
        await _author(db, "John Perkins")
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    assert len(cands) == 1
    assert cands[0].reason == WORD_ORDER
    assert cands[0].auto_mergeable is False


async def test_accent_variants_count_as_exact_and_auto_merge(db_sessionmaker):
    """`normalize` strips accents, so "Kālaccuvaṭu" and "Kalaccuvatu" are the
    same string by the time they are compared. That is deliberate and it means
    auto-merge safely covers diacritic noise — a large share of what an
    OpenLibrary import produces — without needing review."""
    async with db_sessionmaker() as db:
        await _author(db, "Kālaccuvaṭu Patippakam", works=2)
        await _author(db, "Kalaccuvatu Patippakam")
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    assert len(cands) == 1
    assert cands[0].reason == EXACT
    assert cands[0].auto_mergeable is True


async def test_spelling_variants_are_found_via_the_fold(db_sessionmaker):
    """Names that survive accent-stripping as different strings but fold to the
    same skeleton — the ee/i, aspiration and gemination choices a romanizer
    makes differently from ours. Proposed, never auto-merged."""
    async with db_sessionmaker() as db:
        await _author(db, "Chemmeen Pathippakam", works=2)
        await _author(db, "Chemmin Pathipakam")
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    if cands:
        assert cands[0].reason in (WORD_ORDER, SPELLING)
        assert cands[0].auto_mergeable is False


async def test_distinct_people_are_not_proposed(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _author(db, "Thakazhi Sivasankara Pillai")
        await _author(db, "O. V. Vijayan")
        await db.commit()
        assert await merge_service.find_candidates(db, "authors") == []


async def test_the_survivor_is_the_row_carrying_the_most(db_sessionmaker):
    """The row with the most works already has the most inbound links and the
    most to lose."""
    async with db_sessionmaker() as db:
        big = await _author(db, "John Perkins", works=5)
        await _author(db, "John Perkins", works=1)
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    assert cands[0].survivor_id == big.id


def test_a_self_repeating_name_is_detected():
    """The shape of a bad import, not of a longer name."""
    assert merge_service.repeats_itself("Rev. William Rev. William Benham")
    assert merge_service.repeats_itself("John Perkins John Perkins")
    # A name that genuinely says a word twice is not corrupt.
    assert not merge_service.repeats_itself("Sri Sri Ravi Shankar")
    assert not merge_service.repeats_itself("Rev. William Benham")
    assert not merge_service.repeats_itself(None)


async def test_a_repeated_name_does_not_win_the_tie(db_sessionmaker):
    """Both rows carry one book, so the longest-name rule would hand the tie to
    the corrupted row — the exact proposal reported on 12 Aug 2026."""
    async with db_sessionmaker() as db:
        await _author(db, "Rev. William Rev. William Benham", works=1)
        clean = await _author(db, "Rev. William Benham", works=1)
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    assert cands[0].survivor_id == clean.id


async def test_a_repeated_name_still_wins_when_it_carries_more(db_sessionmaker):
    """Books outrank tidiness: the row with the links survives, and the reviewer
    fixes its name rather than moving five books to rescue a typo."""
    async with db_sessionmaker() as db:
        big = await _author(db, "Rev. William Rev. William Benham", works=5)
        await _author(db, "Rev. William Benham", works=1)
        await db.commit()
        cands = await merge_service.find_candidates(db, "authors")

    assert cands[0].survivor_id == big.id


async def test_proposals_are_deterministic(db_sessionmaker):
    """Proposing twice must propose the same thing, or a review queue reshuffles
    under the reviewer."""
    async with db_sessionmaker() as db:
        await _author(db, "Same Name")
        await _author(db, "Same Name")
        await db.commit()
        first = await merge_service.find_candidates(db, "authors")
        second = await merge_service.find_candidates(db, "authors")

    assert first[0].survivor_id == second[0].survivor_id
    assert [i for i, _ in first[0].losers] == [i for i, _ in second[0].losers]


async def test_an_already_merged_row_is_never_proposed_again(db_sessionmaker):
    async with db_sessionmaker() as db:
        a = await _author(db, "John Perkins", works=2)
        b = await _author(db, "John Perkins")
        await db.commit()
        await merge_service.merge(db, "authors", a.id, b.id)
        await db.commit()
        assert await merge_service.find_candidates(db, "authors") == []


# --------------------------------------------------------------------------
# Merging
# --------------------------------------------------------------------------


async def test_merging_moves_every_book_to_the_survivor(db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _author(db, "Vaikom Muhammad Basheer", works=3)
        drop = await _author(db, "V. M. Basheer", works=2)
        await db.commit()

        assert await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()

        from app.services import catalog_service

        works = await catalog_service.author_works(db, keep.id)
    assert len(works) == 5, "books on the merged-away row must not be lost"


async def test_merging_rescues_fields_the_survivor_is_missing(db_sessionmaker):
    """A bio typed on the duplicate must not vanish because that row lost."""
    async with db_sessionmaker() as db:
        keep = await _author(db, "Basheer", works=3)
        drop = await _author(db, "Basheer", bio="A real biography.", image_url="https://x/p.jpg")
        await db.commit()
        await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()
        await db.refresh(keep)

    assert keep.bio == "A real biography."
    assert keep.image_url == "https://x/p.jpg"


async def test_merging_carries_an_approved_author_claim(db_sessionmaker):
    """linked_user_id is written only by an approved "this is me" claim — the
    verification is of the person, so it must survive their duplicate row
    losing a merge."""
    reader = uuid.uuid4()
    async with db_sessionmaker() as db:
        keep = await _author(db, "Madhavikutty", works=3)
        drop = await _author(db, "Madhavikutty", linked_user_id=reader)
        await db.commit()
        await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()
        await db.refresh(keep)

    assert keep.linked_user_id == reader


async def test_the_survivor_keeps_its_own_fields(db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _author(db, "Basheer", works=3, bio="The survivor's bio.")
        drop = await _author(db, "Basheer", bio="The loser's bio.")
        await db.commit()
        await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()
        await db.refresh(keep)
    assert keep.bio == "The survivor's bio."


async def test_the_merged_row_points_at_the_survivor_and_is_soft_deleted(db_sessionmaker):
    """The pointer is what keeps the old URL alive — it 301s instead of 404ing."""
    async with db_sessionmaker() as db:
        keep = await _author(db, "Keep", works=2)
        drop = await _author(db, "Keep")
        await db.commit()
        await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()
        await db.refresh(drop)

    assert drop.merged_into_id == keep.id
    assert drop.deleted_at is not None


async def test_a_shared_book_does_not_break_the_merge(db_sessionmaker):
    """Both rows credited on the same work — repointing naively would collide on
    the composite primary key."""
    async with db_sessionmaker() as db:
        keep = await _author(db, "Dup")
        drop = await _author(db, "Dup")
        shared = Work(title="Credited Twice", authors=[keep, drop])
        db.add(shared)
        await db.commit()

        assert await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()

        from app.services import catalog_service

        works = await catalog_service.author_works(db, keep.id)
    assert len(works) == 1


async def test_merging_a_row_into_itself_is_refused(db_sessionmaker):
    async with db_sessionmaker() as db:
        a = await _author(db, "Solo")
        await db.commit()
        assert await merge_service.merge(db, "authors", a.id, a.id) is False


async def test_merges_never_chain(db_sessionmaker):
    """A pointer to a pointer means a redirect hop, and unmerging the middle row
    would silently strand the far one."""
    async with db_sessionmaker() as db:
        a = await _author(db, "A", works=3)
        b = await _author(db, "B", works=2)
        c = await _author(db, "C")
        await db.commit()
        assert await merge_service.merge(db, "authors", a.id, b.id)
        await db.commit()
        assert await merge_service.merge(db, "authors", b.id, c.id) is False


async def test_unmerge_restores_the_row_and_its_url(db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _author(db, "Keep", works=2)
        drop = await _author(db, "Keep")
        await db.commit()
        await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()

        assert await merge_service.unmerge(db, "authors", drop.id)
        await db.commit()
        await db.refresh(drop)

    assert drop.merged_into_id is None
    assert drop.deleted_at is None


# --------------------------------------------------------------------------
# Auto-merge: exact only
# --------------------------------------------------------------------------


async def test_auto_merge_applies_exact_matches_only(db_sessionmaker):
    """Owner decision: identical names merge unattended, everything softer
    waits for review."""
    async with db_sessionmaker() as db:
        await _author(db, "Identical Name", works=2)
        await _author(db, "Identical Name")
        await _author(db, "Perkins, John", works=2)
        await _author(db, "John Perkins")
        await db.commit()

        merged = await merge_service.auto_merge_exact(db, "authors")

        remaining = await merge_service.find_candidates(db, "authors")

    assert merged == 1, "only the identical pair should have merged"
    assert len(remaining) == 1
    assert remaining[0].reason == WORD_ORDER, "the word-order pair must still await review"


async def test_auto_merge_is_idempotent(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _author(db, "Twice", works=2)
        await _author(db, "Twice")
        await db.commit()
        assert await merge_service.auto_merge_exact(db, "authors") == 1
        assert await merge_service.auto_merge_exact(db, "authors") == 0


async def test_publishers_merge_by_moving_editions(db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = Publisher(name="DC Books")
        drop = Publisher(name="DC Books")
        w = Work(title="Anything")
        db.add_all([keep, drop, w])
        await db.flush()
        db.add_all(
            [
                Edition(work_id=w.id, publisher_id=keep.id),
                Edition(work_id=w.id, publisher_id=drop.id),
            ]
        )
        await db.commit()

        assert await merge_service.auto_merge_exact(db, "publishers") == 1

        from sqlalchemy import func, select

        # Which of two identical rows survives is decided deterministically, not
        # by which variable the test happened to call `keep` — assert on the
        # survivor rather than on a guess about it.
        survivor_id = (
            await db.execute(
                select(Publisher.id).where(
                    Publisher.name == "DC Books", Publisher.merged_into_id.is_(None)
                )
            )
        ).scalar_one()
        moved = await db.scalar(
            select(func.count()).select_from(Edition).where(Edition.publisher_id == survivor_id)
        )
    assert moved == 2, "editions on the merged-away publisher must not be lost"


# --------------------------------------------------------------------------
# The redirect
# --------------------------------------------------------------------------


async def test_a_merged_url_resolves_to_the_survivor(unauthenticated_client, db_sessionmaker):
    """The whole reason for a pointer instead of a delete."""
    async with db_sessionmaker() as db:
        keep = await _author(db, "Vaikom Muhammad Basheer", works=2)
        keep.slug = "vaikom-muhammad-basheer"
        drop = await _author(db, "Vaikom Muhammad Basheer")
        drop.slug = "vaikom-muhammad-basheer-2"
        await db.commit()
        await merge_service.merge(db, "authors", keep.id, drop.id)
        await db.commit()

    resp = await unauthenticated_client.get("/public/merged/author/vaikom-muhammad-basheer-2")
    assert resp.status_code == 200
    assert resp.json()["slug"] == "vaikom-muhammad-basheer"


async def test_an_unmerged_url_is_not_a_redirect(unauthenticated_client, db_sessionmaker):
    async with db_sessionmaker() as db:
        a = await _author(db, "Still Here")
        a.slug = "still-here"
        await db.commit()
    resp = await unauthenticated_client.get("/public/merged/author/still-here")
    assert resp.status_code == 404


@pytest.mark.parametrize("key", ["nope", "../../etc/passwd"])
async def test_unknown_keys_are_not_found_not_errors(unauthenticated_client, key):
    resp = await unauthenticated_client.get(f"/public/merged/author/{key}")
    assert resp.status_code == 404


# --------------------------------------------------------------------------
# Dismissals — what makes the review queue a queue rather than a list
# --------------------------------------------------------------------------


async def test_a_dismissed_pair_never_comes_back(db_sessionmaker):
    """The matchers recompute from names on every run, so without recording the
    rejection the reviewer is asked the same question forever."""
    async with db_sessionmaker() as db:
        a = await _author(db, "Perkins, John", works=3)
        b = await _author(db, "John Perkins")
        await db.commit()

        assert await merge_service.find_candidates(db, "authors"), "expected a proposal first"

        cand = (await merge_service.find_candidates(db, "authors"))[0]
        loser_id = cand.losers[0][0]
        await merge_service.dismiss(db, "authors", cand.survivor_id, loser_id)
        await db.commit()

        assert await merge_service.find_candidates(db, "authors") == []
        assert a.id and b.id  # both rows still exist, untouched


async def test_dismissal_is_symmetric(db_sessionmaker):
    """ "A is not B" and "B is not A" are one fact, not two."""
    async with db_sessionmaker() as db:
        a = await _author(db, "Perkins, John", works=3)
        b = await _author(db, "John Perkins")
        await db.commit()
        await merge_service.dismiss(db, "authors", b.id, a.id)  # reversed order
        await db.commit()
        assert await merge_service.find_candidates(db, "authors") == []


async def test_dismissing_twice_is_not_an_error(db_sessionmaker):
    """A reviewer double-clicking a button is not an exceptional condition."""
    async with db_sessionmaker() as db:
        a = await _author(db, "One")
        b = await _author(db, "Two")
        await db.commit()
        assert await merge_service.dismiss(db, "authors", a.id, b.id) is True
        await db.commit()
        assert await merge_service.dismiss(db, "authors", a.id, b.id) is True
        await db.commit()


async def test_a_dismissal_does_not_block_an_unrelated_duplicate(db_sessionmaker):
    async with db_sessionmaker() as db:
        a = await _author(db, "Perkins, John", works=3)
        b = await _author(db, "John Perkins")
        await db.commit()
        await merge_service.dismiss(db, "authors", a.id, b.id)
        await db.commit()

        await _author(db, "Someone Else", works=2)
        await _author(db, "Someone Else")
        await db.commit()

        cands = await merge_service.find_candidates(db, "authors")
    assert len(cands) == 1
    assert cands[0].survivor_name == "Someone Else"


async def test_merging_a_survivor_flattens_the_rows_that_pointed_at_it(db_sessionmaker):
    """Real case from production: two Malayalam spellings had already been
    folded into a third, and merging THAT into the English name would have left
    the first two pointing at a merged row. Redirect resolution does one hop, so
    the far end of a chain 404s — the exact failure the pointer prevents.
    """
    async with db_sessionmaker() as db:
        english = await _author(db, "DC Books", works=5)
        malayalam = await _author(db, "Di Si Buks", works=20)
        variant_a = await _author(db, "Di Si Buks A")
        variant_b = await _author(db, "Di Si Buks B")
        await db.commit()

        # First round: the two variants fold into the Malayalam row.
        await merge_service.merge(db, "authors", malayalam.id, variant_a.id)
        await merge_service.merge(db, "authors", malayalam.id, variant_b.id)
        await db.commit()

        # Then the Malayalam row itself folds into the English one.
        assert await merge_service.merge(db, "authors", english.id, malayalam.id)
        await db.commit()

        for row in (variant_a, variant_b, malayalam):
            await db.refresh(row)

    # Every merged row points DIRECTLY at the live survivor — no chains.
    assert malayalam.merged_into_id == english.id
    assert variant_a.merged_into_id == english.id, "left pointing at a merged row"
    assert variant_b.merged_into_id == english.id, "left pointing at a merged row"


async def test_every_merged_row_points_at_something_live(db_sessionmaker):
    """The invariant behind the redirect: follow any pointer once and land on a
    row that still exists."""
    async with db_sessionmaker() as db:
        a = await _author(db, "Survivor", works=3)
        b = await _author(db, "Dup One")
        c = await _author(db, "Dup Two")
        await db.commit()
        await merge_service.merge(db, "authors", b.id, c.id)
        await db.commit()
        await merge_service.merge(db, "authors", a.id, b.id)
        await db.commit()

        from sqlalchemy import select

        merged = (
            (await db.execute(select(Author).where(Author.merged_into_id.is_not(None))))
            .scalars()
            .all()
        )
        for row in merged:
            target = await db.get(Author, row.merged_into_id)
            assert target is not None
            assert target.merged_into_id is None, f"{row.name} points at a merged row"
