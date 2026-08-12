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


async def test_merged_duplicates_leave_author_and_publisher_search(client, db_sessionmaker):
    """Folding a duplicate must actually remove it from search — the merge
    soft-deletes the loser, and search filters deleted rows. Without that,
    every merge left the duplicate visible in the app's typeaheads."""
    from sqlalchemy import select

    from app.models import Author, Publisher
    from app.services import catalog_service, merge_service

    await _seed(client)
    async with db_sessionmaker() as db:
        for model, kind in ((Author, "authors"), (Publisher, "publishers")):
            rows = (await db.execute(select(model))).scalars().all()
            keep = rows[0]
            dup = model(name=keep.name, name_translit=keep.name_translit)
            db.add(dup)
            await db.flush()
            assert await merge_service.merge(db, kind, keep.id, dup.id)
        await db.commit()

        authors = await catalog_service.search_authors(db, "Thakazhi")
        publishers = await catalog_service.search_publishers(db, "DC Books")

    assert all(a.merged_into_id is None for a in authors)
    assert all(p.merged_into_id is None for p in publishers)
    assert authors and publishers  # the survivors themselves still match


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


async def test_isbn_search_reconciles_the_two_forms(client):
    """316148410X and 9783161484100 are the same book. Whichever one the
    catalogue happens to hold, either one a reader types must find it."""
    resp = await client.post(
        "/catalog/works", json={"title": "Randamoozham", "isbn": "9783161484100"}
    )
    assert resp.status_code == 201

    for query in ("316148410X", "3-16-148410-X", "9783161484100"):
        resp = await client.get("/catalog/search", params={"q": query})
        assert [w["title"] for w in resp.json()] == ["Randamoozham"], query


async def test_an_isbn10_is_stored_canonically(client):
    """Normalising on write is half the fix (variant lookup is the other half):
    a catalogue that converges on one form makes every later lookup an index hit
    rather than a set of guesses."""
    resp = await client.post("/catalog/works", json={"title": "Chemmeen", "isbn": "81-264-0345-4"})
    assert resp.status_code == 201
    assert resp.json()["editions"][0]["isbn"] == "9788126403455"


async def test_a_checksum_invalid_isbn_is_kept_not_discarded(client):
    """Real catalogues hold misprinted ISBNs. Storing None instead would lose the
    only edition identifier we have — and it must still be findable."""
    resp = await client.post("/catalog/works", json={"title": "Misprint", "isbn": "9788126403454"})
    assert resp.status_code == 201
    assert resp.json()["editions"][0]["isbn"] == "9788126403454"

    resp = await client.get("/catalog/search", params={"q": "9788126403454"})
    assert [w["title"] for w in resp.json()] == ["Misprint"]


async def test_import_matching_stays_strict(client):
    """The CSV import takes the top hit as THE match — a typo'd title must
    stay unmatched (fuzzy=False) rather than latch onto a similar book."""
    await _seed(client)
    resp = await client.post("/import/preview", json={"csv": "Title\nChemeen"})
    assert resp.status_code == 200
    row = resp.json()["rows"][0]
    assert row["title"] == "Chemeen"
    assert row["match"] is None
