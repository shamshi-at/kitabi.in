from sqlalchemy import text


async def test_create_work_manual(client):
    resp = await client.post(
        "/catalog/works",
        json={
            "title": "Ponniyin Selvan — Vol I",
            "author_names": ["Kalki Krishnamurthy"],
            "publisher_name": "Vanathi Pathippakam",
            "language": "Tamil",
            "series_name": "Ponniyin Selvan",
            "series_number": 1,
            "isbn": "9788184930666",
            "page_count": 520,
            "format": "Paperback",
            "genre_names": ["Historical", "Fiction"],
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "Ponniyin Selvan — Vol I"
    assert body["authors"][0]["name"] == "Kalki Krishnamurthy"
    assert len(body["genres"]) == 2
    edition = body["editions"][0]
    assert edition["isbn"] == "9788184930666"
    assert edition["series"]["name"] == "Ponniyin Selvan"
    assert edition["series_number"] == 1
    assert edition["publisher"]["name"] == "Vanathi Pathippakam"


async def test_create_work_reuses_existing_author(client):
    first = await client.post(
        "/catalog/works", json={"title": "Randamoozham", "author_names": ["M.T. Vasudevan Nair"]}
    )
    second = await client.post(
        "/catalog/works", json={"title": "Kaalam", "author_names": ["M.T. Vasudevan Nair"]}
    )
    assert first.json()["authors"][0]["id"] == second.json()["authors"][0]["id"]


async def test_get_and_patch_work(client):
    created = await client.post("/catalog/works", json={"title": "Draft Title"})
    work_id = created.json()["id"]

    got = await client.get(f"/catalog/works/{work_id}")
    assert got.status_code == 200
    assert got.json()["title"] == "Draft Title"

    patched = await client.patch(
        f"/catalog/works/{work_id}",
        json={"title": "Final Title", "author_names": ["New Author"]},
    )
    assert patched.status_code == 200
    assert patched.json()["title"] == "Final Title"
    assert patched.json()["authors"][0]["name"] == "New Author"


async def test_get_work_404(client):
    resp = await client.get("/catalog/works/00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


async def test_search_by_title(client):
    await client.post("/catalog/works", json={"title": "Khasakkinte Itihasam"})
    resp = await client.get("/catalog/search", params={"q": "khasak"})
    assert resp.status_code == 200
    titles = [w["title"] for w in resp.json()]
    assert "Khasakkinte Itihasam" in titles


async def test_search_by_author(client):
    await client.post("/catalog/works", json={"title": "Aarachar", "author_names": ["K.R. Meera"]})
    resp = await client.get("/catalog/search", params={"q": "meera"})
    assert resp.status_code == 200
    assert any(w["title"] == "Aarachar" for w in resp.json())


async def test_search_by_isbn(client):
    await client.post("/catalog/works", json={"title": "Has ISBN", "isbn": "9781234567897"})
    resp = await client.get("/catalog/search", params={"q": "9781234567897"})
    assert resp.status_code == 200
    assert resp.json()[0]["title"] == "Has ISBN"


async def test_isbn_lookup_hits_openlibrary_and_caches(client):
    first = await client.get("/catalog/isbn/9780802162175")
    assert first.status_code == 200
    body = first.json()
    assert body["title"] == "The Covenant of Water"
    assert body["authors"][0]["name"] == "Abraham Verghese"
    assert body["editions"][0]["isbn"] == "9780802162175"
    assert body["editions"][0]["cover_url"] == "https://covers.openlibrary.org/b/id/12345-L.jpg"

    # Second lookup must not need OpenLibrary again — served from the cache.
    second = await client.get("/catalog/isbn/9780802162175")
    assert second.status_code == 200
    assert second.json()["id"] == body["id"]


async def test_isbn_lookup_not_found(client):
    resp = await client.get("/catalog/isbn/0000000000000")
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


async def test_author_browse(client):
    created = await client.post(
        "/catalog/works", json={"title": "Naalukettu", "author_names": ["M.T. Vasudevan Nair"]}
    )
    author_id = created.json()["authors"][0]["id"]

    resp = await client.get(f"/catalog/authors/{author_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["author"]["name"] == "M.T. Vasudevan Nair"
    assert any(w["title"] == "Naalukettu" for w in body["works"])


async def test_publisher_browse(client):
    created = await client.post(
        "/catalog/works",
        json={"title": "Ente Katha", "publisher_name": "DC Books", "author_names": ["Kamala Das"]},
    )
    publisher_id = created.json()["editions"][0]["publisher"]["id"]

    resp = await client.get(f"/catalog/publishers/{publisher_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["publisher"]["name"] == "DC Books"
    assert any(w["title"] == "Ente Katha" for w in body["works"])


async def test_link_translation(client):
    a = await client.post("/catalog/works", json={"title": "Mayyazhippuzhayude Theerangalil"})
    b = await client.post("/catalog/works", json={"title": "On the Banks of the Mayyazhi"})
    a_id, b_id = a.json()["id"], b.json()["id"]

    resp = await client.post(
        f"/catalog/works/{a_id}/link-translation", json={"other_work_id": b_id}
    )
    assert resp.status_code == 204

    a_after = (await client.get(f"/catalog/works/{a_id}")).json()
    b_after = (await client.get(f"/catalog/works/{b_id}")).json()
    assert a_after["translation_group_id"] is not None
    assert a_after["translation_group_id"] == b_after["translation_group_id"]


async def test_translation_group_rating_aggregates_for_display_only(client, db_sessionmaker):
    """Each translation keeps its own independent rating pool (product
    decision, 5 Jul 2026) — translation_group_rating is a read-time display
    aggregate over the group, not something either Work's own rating merges
    into."""
    a = await client.post("/catalog/works", json={"title": "Aatmakatha"})
    b = await client.post("/catalog/works", json={"title": "An Autobiography"})
    a_id, b_id = a.json()["id"], b.json()["id"]
    await client.post(f"/catalog/works/{a_id}/link-translation", json={"other_work_id": b_id})

    # No rating-write endpoint exists yet (Phase 3) — set directly.
    async with db_sessionmaker() as session:
        await session.execute(
            text("UPDATE works SET aggregate_rating = 4.0 WHERE id = :id"), {"id": a_id}
        )
        await session.execute(
            text("UPDATE works SET aggregate_rating = 5.0 WHERE id = :id"), {"id": b_id}
        )
        await session.commit()

    a_after = (await client.get(f"/catalog/works/{a_id}")).json()
    b_after = (await client.get(f"/catalog/works/{b_id}")).json()

    assert a_after["aggregate_rating"] == 4.0
    assert b_after["aggregate_rating"] == 5.0
    assert a_after["translation_group_rating"] == 4.5
    assert b_after["translation_group_rating"] == 4.5


async def test_translation_group_rating_null_without_a_link(client):
    created = await client.post("/catalog/works", json={"title": "Standalone"})
    body = (await client.get(f"/catalog/works/{created.json()['id']}")).json()
    assert body["translation_group_rating"] is None
