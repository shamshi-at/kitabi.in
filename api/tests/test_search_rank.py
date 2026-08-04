"""Cross-type search relevance.

The reported failure: typing "dc books" put four books that merely contain the
word "books" above the publisher literally called DC Books. The cause was not
bad matching — each type was found correctly — it was that the combined list had
no ordering, so it concatenated books, then authors, then publishers.

These tests are mostly about ORDER, because ordering is what was broken.
"""

import pytest

from app.models import Author, Edition, Publisher, Work
from app.services import public_service, search_rank
from app.services.search_rank import normalize, score

# --------------------------------------------------------------------------
# The scorer
# --------------------------------------------------------------------------


def test_an_exact_match_beats_everything_else():
    q = "dc books"
    assert score(q, label="DC Books") > score(q, label="DC Books International")
    assert score(q, label="DC Books") > score(q, label="The girl who hated books")
    assert score(q, label="DC Books") > score(q, label="Educa Books /Diamond")
    assert score(q, label="DC Books") > score(q, label="Booking")


def test_the_bands_are_guarantees_not_coincidences():
    """An exact match must beat a prefix match must beat a whole-word match, no
    matter what similarity or popularity says. That is why the scale is banded
    rather than a weighted blend of continuous signals."""
    q = "books"
    exact = score(q, label="Books", popularity=0)
    prefix = score(q, label="Books Illustrated", popularity=1000, popularity_ceiling=1)
    words = score(q, label="A history of books", popularity=1000, popularity_ceiling=1)
    assert exact > prefix > words


def test_popularity_only_breaks_ties():
    """A publisher with 200 books beats one with 2 when they match equally —
    and never otherwise."""
    big = score("books", label="Some Books", popularity=200, popularity_ceiling=200)
    small = score("books", label="Some Books", popularity=1, popularity_ceiling=200)
    assert big > small
    # …but popularity can never lift a worse match over a better one.
    assert score("dc books", label="DC Books", popularity=0) > big


def test_a_shorter_prefix_match_ranks_higher():
    q = "dc"
    assert score(q, label="DC Books") > score(q, label="DC Books International Distribution")


def test_word_order_does_not_matter():
    assert score("books dc", label="DC Books") >= search_rank.ALL_WORDS


def test_a_partial_match_never_outranks_a_complete_one():
    q = "dc books"
    complete = score(q, label="Books DC")
    partial = score(q, label="The girl who hated books")
    assert complete > partial


def test_unrelated_text_scores_zero():
    assert score("dc books", label="Ponniyin Selvan") == search_rank.WEAK
    assert score("dc books", label=None) == search_rank.WEAK
    assert score("", label="DC Books") == search_rank.WEAK


def test_normalize_strips_accents_so_transliterated_names_are_typeable():
    """This catalogue is full of names like Bibhūtibhūshaṇa and Ḥāfiẓ. A reader
    with an ordinary keyboard has to be able to reach them."""
    assert normalize("Bibhūtibhūshaṇa") == "bibhutibhushana"
    assert normalize("Ḥāfiẓ") == "hafiz"
    assert normalize("  DC  Books! ") == "dc books"


def test_cross_script_scoring_uses_the_romanized_twin():
    """A Latin query has no useful direct comparison to a native-script title;
    its transliteration does. Without this the title is merely found, not
    ranked."""
    native = score(
        "arachchar",
        label="ആരാച്ചാർ",
        translit="aaraacchaar",
        fold="arachar",
        query_translit="arachchar",
        query_fold="arachar",
    )
    assert native >= search_rank.ALL_WORDS


def test_rank_is_a_total_order():
    """Equal scores must not reshuffle between requests for reasons nobody can
    see — a page that reorders itself on refresh looks broken."""
    items = [
        {"label": "B", "score": 0.5, "tie": 1},
        {"label": "A", "score": 0.5, "tie": 1},
        {"label": "C", "score": 0.5, "tie": 0},
    ]
    once = [i["label"] for i in search_rank.rank(list(items), 10)]
    twice = [i["label"] for i in search_rank.rank(list(reversed(items)), 10)]
    assert once == twice == ["C", "A", "B"]


def test_rank_drops_non_matches_and_respects_the_limit():
    items = [
        {"label": "hit", "score": 0.9},
        {"label": "miss", "score": 0.0},
        {"label": "hit2", "score": 0.7},
    ]
    out = search_rank.rank(items, 1)
    assert [i["label"] for i in out] == ["hit"]


# --------------------------------------------------------------------------
# Through the suggest endpoint — the reported bug, end to end
# --------------------------------------------------------------------------


async def test_dc_books_puts_the_publisher_first(db_sessionmaker):
    """The exact scenario from the report."""
    async with db_sessionmaker() as db:
        dc = Publisher(name="DC Books", slug="dc-books")
        db.add_all(
            [
                dc,
                Publisher(name="Educa Books /Diamond", slug="educa-books"),
                Publisher(name="Turtleback Books Distributed by Demco Media", slug="turtleback"),
                Author(name="Booking", slug="booking"),
                Work(title="The girl who hated books", slug="girl-who-hated-books"),
                Work(title="Author catalogue of printed books in Tamil language", slug="tamil-cat"),
            ]
        )
        await db.flush()
        # Give DC Books some weight, as it has in the real catalogue.
        w = Work(title="Anything")
        db.add(w)
        await db.flush()
        for _ in range(5):
            db.add(Edition(work_id=w.id, publisher_id=dc.id))
        await db.commit()

        page = await public_service.suggest(db, "dc books")

    assert page.suggestions, "expected suggestions for a query that clearly matches"
    top = page.suggestions[0]
    assert top.label == "DC Books", [s.label for s in page.suggestions]
    assert top.kind == "publisher"


async def test_an_exact_book_title_outranks_an_author_who_merely_contains_it(db_sessionmaker):
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Work(title="Kayar", slug="kayar"),
                Author(name="Kayarambath Somebody", slug="kayarambath"),
            ]
        )
        await db.commit()
        page = await public_service.suggest(db, "kayar")

    assert page.suggestions[0].label == "Kayar"
    assert page.suggestions[0].kind == "book"


async def test_an_author_search_puts_the_author_first(db_sessionmaker):
    """Searching a person's name should offer the person, not only their books."""
    async with db_sessionmaker() as db:
        a = Author(name="Thakazhi Sivasankara Pillai", slug="thakazhi")
        db.add(a)
        await db.flush()
        db.add_all(
            [
                Work(title="Chemmeen", slug="chemmeen-x", authors=[a]),
                Work(title="Kayar", slug="kayar-x", authors=[a]),
            ]
        )
        await db.commit()
        page = await public_service.suggest(db, "thakazhi sivasankara pillai")

    assert page.suggestions[0].kind == "author"


async def test_suggestions_stay_bounded(db_sessionmaker):
    async with db_sessionmaker() as db:
        for i in range(40):
            db.add(Work(title=f"Books Volume {i}", slug=f"books-vol-{i}"))
        await db.commit()
        page = await public_service.suggest(db, "books", limit=5)
    assert len(page.suggestions) <= 5


@pytest.mark.parametrize("q", ["", "   "])
async def test_an_empty_query_suggests_nothing(db_sessionmaker, q):
    async with db_sessionmaker() as db:
        db.add(Work(title="Anything", slug="anything"))
        await db.commit()
        page = await public_service.suggest(db, q)
    assert page.suggestions == []


async def test_the_search_page_leads_with_the_best_matching_section(db_sessionmaker):
    """Grouping by type is right for a results page, but the group holding the
    single best result should come first. Searching a publisher's exact name
    should not open with books that merely share a word."""
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Publisher(name="DC Books", slug="dc-books-2"),
                Work(title="A book about books", slug="about-books"),
            ]
        )
        await db.commit()
        page = await public_service.search_page(db, "dc books")

    assert page.order[0] == "publisher", page.order
    assert page.publishers and page.publishers[0].name == "DC Books"


async def test_the_search_page_still_leads_with_books_for_a_title(db_sessionmaker):
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Work(title="Chemmeen", slug="chemmeen-s"),
                Publisher(name="Chemmeen Press", slug="chemmeen-press"),
            ]
        )
        await db.commit()
        page = await public_service.search_page(db, "chemmeen")
    assert page.order[0] == "book", page.order
