"""Typo-tolerant, relevance-ranked global search — runs against real Postgres
with pg_trgm, so these exercise the actual `%`/`<%`/similarity operators."""


async def _seed(client) -> None:
    for title, author, publisher in (
        ("Chemmeen", "Thakazhi Sivasankara Pillai", "DC Books"),
        ("Kayar", "Thakazhi Sivasankara Pillai", "DC Books"),
        ("Aarachar", "K.R. Meera", "Green Books"),
    ):
        resp = await client.post(
            "/catalog/works",
            json={"title": title, "author_names": [author], "publisher_name": publisher},
        )
        assert resp.status_code == 201


async def test_search_matches_typo_in_title(client):
    await _seed(client)
    resp = await client.get("/catalog/search", params={"q": "Chemeen"})  # typo
    titles = [w["title"] for w in resp.json()]
    assert titles and titles[0] == "Chemmeen"


async def test_search_matches_typo_in_author_name(client):
    await _seed(client)
    resp = await client.get("/catalog/search", params={"q": "Thakazi"})  # typo
    titles = {w["title"] for w in resp.json()}
    assert {"Chemmeen", "Kayar"} <= titles


async def test_search_ranks_the_exact_title_first(client):
    await _seed(client)
    resp = await client.get("/catalog/search", params={"q": "Kayar"})
    titles = [w["title"] for w in resp.json()]
    assert titles[0] == "Kayar"


async def test_search_all_is_fuzzy_across_all_three_sections(client):
    await _seed(client)
    # Author typo reaches the authors section...
    resp = await client.get("/catalog/search/all", params={"q": "Thakazi"})
    body = resp.json()
    assert any(a["name"] == "Thakazhi Sivasankara Pillai" for a in body["authors"])
    # ...and a publisher typo reaches the publishers section.
    resp = await client.get("/catalog/search/all", params={"q": "DC Bookz"})
    body = resp.json()
    assert any(p["name"] == "DC Books" for p in body["publishers"])


async def test_isbn_search_stays_exact(client):
    resp = await client.post(
        "/catalog/works", json={"title": "Randamoozham", "isbn": "9783161484100"}
    )
    assert resp.status_code == 201
    resp = await client.get("/catalog/search", params={"q": "9783161484100"})
    assert [w["title"] for w in resp.json()] == ["Randamoozham"]
    # A near-miss ISBN matches nothing — numbers must never fuzz.
    resp = await client.get("/catalog/search", params={"q": "9783161484101"})
    assert resp.json() == []


async def test_import_matching_stays_strict(client):
    """The CSV import takes the top hit as THE match — a typo'd title must
    stay unmatched (fuzzy=False) rather than latch onto a similar book."""
    await _seed(client)
    resp = await client.post("/import/preview", json={"csv": "Title\nChemeen"})
    assert resp.status_code == 200
    row = resp.json()["rows"][0]
    assert row["title"] == "Chemeen"
    assert row["match"] is None
