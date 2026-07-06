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


async def test_author_typeahead(client):
    await client.post(
        "/catalog/works", json={"title": "Randamoozham", "author_names": ["M.T. Vasudevan Nair"]}
    )
    resp = await client.get("/catalog/authors", params={"q": "vasudevan"})
    assert resp.status_code == 200
    names = [a["name"] for a in resp.json()]
    assert "M.T. Vasudevan Nair" in names


async def test_publisher_typeahead(client):
    await client.post(
        "/catalog/works", json={"title": "Balyakalasakhi", "publisher_name": "Mathrubhumi Books"}
    )
    resp = await client.get("/catalog/publishers", params={"q": "mathru"})
    assert resp.status_code == 200
    names = [p["name"] for p in resp.json()]
    assert "Mathrubhumi Books" in names


async def test_typeahead_no_match_is_empty(client):
    resp = await client.get("/catalog/authors", params={"q": "zzz-nobody-zzz"})
    assert resp.status_code == 200
    assert resp.json() == []


async def test_create_author_with_details(client):
    resp = await client.post(
        "/catalog/authors",
        json={
            "name": "Benyamin",
            "pen_name": "Benny Daniel",
            "primary_language": "Malayalam",
            "image_url": "https://example.com/benyamin.jpg",
            "bio": "Author of Aadujeevitham.",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Benyamin"
    assert body["primary_language"] == "Malayalam"
    assert body["image_url"] == "https://example.com/benyamin.jpg"

    # Browse exposes the fuller detail (bio) too.
    detail = (await client.get(f"/catalog/authors/{body['id']}")).json()
    assert detail["author"]["bio"] == "Author of Aadujeevitham."
    assert detail["author"]["primary_language"] == "Malayalam"


async def test_create_author_is_idempotent_on_name(client):
    first = await client.post("/catalog/authors", json={"name": "Perumal Murugan"})
    second = await client.post(
        "/catalog/authors", json={"name": "perumal murugan", "primary_language": "Tamil"}
    )
    assert first.json()["id"] == second.json()["id"]


async def test_create_publisher_with_details(client):
    resp = await client.post(
        "/catalog/publishers",
        json={"name": "Green Books", "primary_language": "Malayalam"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Green Books"
    assert body["primary_language"] == "Malayalam"


async def test_create_work_by_author_and_publisher_id(client):
    author = (await client.post("/catalog/authors", json={"name": "O.V. Vijayan"})).json()
    publisher = (await client.post("/catalog/publishers", json={"name": "DC Books"})).json()

    created = await client.post(
        "/catalog/works",
        json={
            "title": "Khasakkinte Itihasam",
            "author_ids": [author["id"]],
            "publisher_id": publisher["id"],
        },
    )
    assert created.status_code == 201
    body = created.json()
    assert body["authors"][0]["id"] == author["id"]
    assert body["editions"][0]["publisher"]["id"] == publisher["id"]


async def test_global_search_returns_all_sections(client):
    await client.post(
        "/catalog/works",
        json={
            "title": "Aadujeevitham",
            "author_names": ["Benyamin Global"],
            "publisher_name": "Benyamin Publishing House",
        },
    )
    resp = await client.get("/catalog/search/all", params={"q": "benyamin"})
    assert resp.status_code == 200
    body = resp.json()
    assert set(body) == {"works", "authors", "publishers"}
    assert any(a["name"] == "Benyamin Global" for a in body["authors"])
    assert any(p["name"] == "Benyamin Publishing House" for p in body["publishers"])
    assert any(w["title"] == "Aadujeevitham" for w in body["works"])


async def test_browse_works_authors_publishers_paged(client):
    # Seed a few works spanning authors + publishers.
    for i in range(3):
        await client.post(
            "/catalog/works",
            json={
                "title": f"Browse Title {i}",
                "author_names": [f"Browse Author {i}"],
                "publisher_name": f"Browse House {i}",
            },
        )

    works = await client.get("/catalog/browse/works", params={"limit": 2, "offset": 0})
    assert works.status_code == 200
    assert len(works.json()) == 2
    # Alphabetical ordering — page 2 continues where page 1 left off.
    page2 = await client.get("/catalog/browse/works", params={"limit": 2, "offset": 2})
    assert page2.status_code == 200
    first_page_titles = {w["title"] for w in works.json()}
    assert all(w["title"] not in first_page_titles for w in page2.json())

    authors = await client.get("/catalog/browse/authors", params={"limit": 100})
    assert authors.status_code == 200
    assert any(a["name"] == "Browse Author 0" for a in authors.json())

    publishers = await client.get("/catalog/browse/publishers", params={"limit": 100})
    assert publishers.status_code == 200
    assert any(p["name"] == "Browse House 1" for p in publishers.json())


async def test_browse_works_filter_and_sort(client):
    await client.post(
        "/catalog/works",
        json={"title": "Older Book", "language": "Malayalam", "first_publish_year": 1970},
    )
    await client.post(
        "/catalog/works",
        json={"title": "Newer Book", "language": "Malayalam", "first_publish_year": 2010},
    )
    await client.post(
        "/catalog/works",
        json={"title": "Tamil Book", "language": "Tamil", "first_publish_year": 1990},
    )

    # Language filter.
    mal = await client.get("/catalog/browse/works", params={"language": "Malayalam", "limit": 100})
    titles = [w["title"] for w in mal.json()]
    assert "Older Book" in titles and "Newer Book" in titles
    assert "Tamil Book" not in titles

    # Sort by newest first.
    newest = await client.get(
        "/catalog/browse/works", params={"language": "Malayalam", "sort": "year_desc", "limit": 100}
    )
    ny = [w["title"] for w in newest.json()]
    assert ny.index("Newer Book") < ny.index("Older Book")

    # Sort by oldest first.
    oldest = await client.get(
        "/catalog/browse/works", params={"language": "Malayalam", "sort": "year_asc", "limit": 100}
    )
    oy = [w["title"] for w in oldest.json()]
    assert oy.index("Older Book") < oy.index("Newer Book")


async def test_browse_works_sort_by_author(client):
    await client.post("/catalog/works", json={"title": "Zeta Work", "author_names": ["Anand"]})
    await client.post("/catalog/works", json={"title": "Alpha Work", "author_names": ["Zacharia"]})
    resp = await client.get("/catalog/browse/works", params={"sort": "author", "limit": 100})
    assert resp.status_code == 200
    titles = [w["title"] for w in resp.json()]
    # Sorted by author name (Anand before Zacharia), not by title.
    assert titles.index("Zeta Work") < titles.index("Alpha Work")


async def test_browse_languages_lists_distinct(client):
    await client.post("/catalog/works", json={"title": "L1", "language": "Malayalam"})
    await client.post("/catalog/works", json={"title": "L2", "language": "Tamil"})
    await client.post("/catalog/works", json={"title": "L3", "language": "Malayalam"})
    resp = await client.get("/catalog/browse/languages")
    assert resp.status_code == 200
    langs = resp.json()
    assert "Malayalam" in langs and "Tamil" in langs
    assert langs == sorted(langs)  # distinct + ordered


async def test_edition_buy_links_wired_and_patchable(client):
    created = await client.post(
        "/catalog/works", json={"title": "Buyable", "isbn": "9789999999999"}
    )
    edition = created.json()["editions"][0]
    # [WIRED] — the field exists and defaults to an empty list (column is null).
    assert edition["buy_links"] == []

    patched = await client.patch(
        f"/catalog/editions/{edition['id']}",
        json={
            "buy_links": [
                {"retailer": "Amazon", "url": "https://amazon.in/dp/x"},
                {"retailer": "Flipkart", "url": "https://flipkart.com/y"},
            ]
        },
    )
    assert patched.status_code == 200
    links = patched.json()["buy_links"]
    assert [b["retailer"] for b in links] == ["Amazon", "Flipkart"]
    assert links[0]["url"] == "https://amazon.in/dp/x"


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
