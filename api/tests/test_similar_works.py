"""Typo-tolerant duplicate detection (GET /catalog/works/similar) — trigram
matching against real Postgres with pg_trgm (migration 000018 runs in the test
container), so these exercise the actual similarity operators, not mocks."""


async def _seed(client) -> None:
    for title in ("Chemmeen", "Kayar", "Khasakkinte Itihasam"):
        resp = await client.post("/catalog/works", json={"title": title})
        assert resp.status_code == 201


async def test_similar_finds_a_typo_match(client):
    await _seed(client)
    resp = await client.get("/catalog/works/similar", params={"title": "Chemeen"})  # typo
    assert resp.status_code == 200
    titles = [w["title"] for w in resp.json()]
    assert titles and titles[0] == "Chemmeen"


async def test_similar_matches_partial_typing(client):
    await _seed(client)
    # Mid-typing containment: "khasak" should surface the long title.
    resp = await client.get("/catalog/works/similar", params={"title": "khasak"})
    titles = [w["title"] for w in resp.json()]
    assert "Khasakkinte Itihasam" in titles


async def test_similar_returns_nothing_for_unrelated_title(client):
    await _seed(client)
    resp = await client.get("/catalog/works/similar", params={"title": "Wuthering Heights"})
    assert resp.status_code == 200
    assert resp.json() == []


async def test_similar_ignores_too_short_queries(client):
    await _seed(client)
    resp = await client.get("/catalog/works/similar", params={"title": "Ch"})
    assert resp.status_code == 200
    assert resp.json() == []
