"""However a reader spells it, they find the book.

`*_translit` stores ONE romanization, but readers type many — long vowels
doubled or not, aspirates with or without the h, Tamil ச as ch or s, consonants
doubled or single. The fold column collapses those choices on both the stored
side and the query side so they meet regardless.

Runs against real Postgres, so the trigram operators, the migration's indexes
and the actual search SQL are what's exercised — not a stub.
"""

import pytest

from app.services.translit import fold

# (title, language, the spellings a reader might plausibly type)
BOOKS = [
    ("ചെമ്മീൻ", "Malayalam", ["chemmeen", "chemmin", "chemeen", "Chemmeen"]),
    ("അപൂർണ്ണൻ", "Malayalam", ["apoornan", "apurnan", "apoornnan"]),
    ("பொன்னியின் செல்வன்", "Tamil", ["ponniyin selvan", "ponniyin chelvan"]),
    ("திருக்குறள்", "Tamil", ["thirukkural", "tirukural"]),
    ("गीतांजलि", "Hindi", ["gitanjali", "geetanjali"]),
]


async def _seed(client) -> None:
    for title, language, _ in BOOKS:
        resp = await client.post(
            "/catalog/works", json={"title": title, "language": language, "author_names": []}
        )
        assert resp.status_code == 201, resp.text


def test_fold_collapses_the_spellings_readers_disagree_on():
    # long vs short vowels, gemination, and the sibilant series all collapse
    assert fold("ചെമ്മീൻ") == fold("chemmin") == fold("chemmeen")
    # aspiration is optional to a typist
    assert fold("திருக்குறள்") == fold("thirukkural") == fold("tirukural")
    # Tamil ச reads as ch or s depending on who is typing
    assert fold("பொன்னியின் செல்வன்") == fold("ponniyin selvan")
    # …and the anusvara that ITRANS hears as m, a reader writes as n
    assert fold("गीतांजलि") == fold("gitanjali") == fold("geetanjali")


def test_fold_is_none_for_nothing_to_fold():
    assert fold(None) is None
    assert fold("   ") is None


@pytest.mark.parametrize(("title", "_lang", "spellings"), BOOKS)
async def test_every_spelling_finds_the_book(client, title, _lang, spellings):
    """The point of the feature: one book, many spellings, one result."""
    await _seed(client)
    for typed in spellings:
        resp = await client.get("/catalog/search", params={"q": typed})
        assert resp.status_code == 200
        titles = [w["title"] for w in resp.json()]
        assert title in titles, f"{typed!r} did not find {title!r} (got {titles})"


async def test_native_script_query_still_works(client):
    """The fold must not cost the cross-script matching it sits beside."""
    await _seed(client)
    for typed in ("ചെമ്മീൻ", "திருக்குறள்"):
        resp = await client.get("/catalog/search", params={"q": typed})
        assert typed in [w["title"] for w in resp.json()]


async def test_a_different_book_is_not_dragged_in(client):
    """Folding is lossy, so guard the precision side too: an unrelated title
    must not surface just because the skeleton is short."""
    await _seed(client)
    resp = await client.get("/catalog/search", params={"q": "gitanjali"})
    titles = [w["title"] for w in resp.json()]
    assert "गीतांजलि" in titles
    assert "ചെമ്മീൻ" not in titles
