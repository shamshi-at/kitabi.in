"""Duplicates the word-set matchers structurally cannot see.

EXACT, WORD_ORDER and SPELLING all key on a *set of words*, which assumes the
two spellings agree about where the words are. An initialism is exactly the case
where they do not: "DC Books" from the spine, "Ḍi Si Buks" from a transliterating
cataloguer and "ഡിസി ബുക്സ്" from the Malayalam cover are one house whose folds
are `dc buks`, `di si buks` and `disi buks` — three different word sets, and the
queue walked past all three (owner report, 5 Sep 2026).

Nothing here auto-merges. Only EXACT does, and these are proposals a human
approves — which is the whole licence for a key this loose.
"""

import pytest

from app.models import Publisher
from app.services import merge_service
from app.services.catalog_service import _get_or_create
from app.services.merge_service import EXACT, INITIALISM, SPACING, _key_loose, reads_as_initials
from app.services.translit import fold


def key(name: str) -> str:
    return _key_loose(fold(name))


@pytest.mark.parametrize(
    "names",
    [
        # The report, exactly.
        ("DC Books", "Ḍi Si Buks", "ഡിസി ബുക്സ്"),
        # The same move on a different house — initials are how Malayalam
        # publishing writes N.B.S., S.P.C.S., C.I.C.C.
        ("NBS", "En Bi Es"),
        # Spacing alone, no initials involved.
        ("Kālaccuvaṭu", "Kala Ccuvatu"),
    ],
)
def test_spellings_of_one_house_share_a_key(names):
    keys = {key(n) for n in names}
    assert len(keys) == 1, f"{names} produced {keys}"


@pytest.mark.parametrize(
    ("a", "b"),
    [
        # Sat in the same search as the DC Books rows and is a different house.
        ("DC Books", "Ḍi. Vi. Ke. Mūrti"),
        # An imprint or branch is not the parent — keying them together would
        # quietly propose folding away a real distinction.
        ("DC Books", "DC Books Kottayam"),
        # Two genuinely different houses that happen to be short.
        ("NBS", "SPCS"),
        # The pair this honestly cannot bridge: the vowels disagree, and a map
        # that guessed at them would fold names that are not the same.
        ("Si. Ee. Si. Si. Bukkus Haus", "സി. ഐ. സി. സി. ബുക്ക് ഹൗസ്"),
    ],
)
def test_different_houses_stay_apart(a, b):
    assert key(a) != key(b)


def test_only_a_short_all_consonant_run_is_read_as_initials():
    assert reads_as_initials(fold("DC Books")) is True
    # A word with a vowel is a word, which is also the "is it initials?" test.
    assert reads_as_initials(fold("Ḍi Si Buks")) is False
    # Longer than an initialism plausibly runs — likelier a fold artefact.
    assert reads_as_initials(fold("Rhythms")) is False


async def test_the_queue_now_proposes_the_three_spellings(db_sessionmaker):
    async with db_sessionmaker() as db:
        for name in ("DC Books", "Ḍi Si Buks", "ഡിസി ബുക്സ്", "Ḍi. Vi. Ke. Mūrti"):
            await _get_or_create(db, Publisher, name)
        await db.commit()

    async with db_sessionmaker() as db:
        candidates = await merge_service.find_candidates(db, "publishers")

    clusters = [c for c in candidates if c.reason == INITIALISM]
    assert len(clusters) == 1, [c.reason for c in candidates]
    cluster = clusters[0]
    members = {cluster.survivor_name, *(name for _, name in cluster.losers)}
    assert members == {"DC Books", "Ḍi Si Buks", "ഡിസി ബുക്സ്"}
    # The house that merely shared the search is not in it.
    assert "Ḍi. Vi. Ke. Mūrti" not in members


async def test_a_spacing_only_cluster_says_so(db_sessionmaker):
    """The reason has to name what actually bridged them, or a wrong proposal is
    mysterious instead of arguable."""
    async with db_sessionmaker() as db:
        for name in ("Kālaccuvaṭu", "Kala Ccuvatu"):
            await _get_or_create(db, Publisher, name)
        await db.commit()

    async with db_sessionmaker() as db:
        candidates = await merge_service.find_candidates(db, "publishers")

    reasons = {c.reason for c in candidates}
    assert SPACING in reasons
    assert INITIALISM not in reasons


async def test_nothing_new_merges_itself(db_sessionmaker):
    """Only an identical name merges unattended. A key this loose proposing an
    auto-merge is the one outcome that would be unrecoverable in bulk."""
    async with db_sessionmaker() as db:
        for name in ("DC Books", "Ḍi Si Buks", "ഡിസി ബുക്സ്", "Kālaccuvaṭu", "Kala Ccuvatu"):
            await _get_or_create(db, Publisher, name)
        await db.commit()

    async with db_sessionmaker() as db:
        for candidate in await merge_service.find_candidates(db, "publishers"):
            if candidate.reason in (SPACING, INITIALISM):
                assert not candidate.auto_mergeable
            assert candidate.auto_mergeable == (candidate.reason == EXACT)


async def test_a_stronger_matcher_still_claims_its_rows_first(db_sessionmaker):
    """The loose key would also group an identical pair. Evidence order has to
    hold, or every cluster would arrive labelled with the weakest reason that
    fits it."""
    async with db_sessionmaker() as db:
        # Added directly: `_get_or_create` is case-insensitive by design and
        # would hand back one row, which is the duplicate we need two of.
        for name in ("Mathrubhumi Books", "mathrubhumi books"):
            db.add(Publisher(name=name, name_fold=fold(name)))
        await db.commit()

    async with db_sessionmaker() as db:
        candidates = await merge_service.find_candidates(db, "publishers")

    assert [c.reason for c in candidates] == [EXACT]
