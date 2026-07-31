async def test_get_me_requires_bootstrap(client):
    resp = await client.get("/me")
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_bootstrapped"


async def test_get_me_after_bootstrap(client):
    await client.post("/auth/bootstrap")
    resp = await client.get("/me")
    assert resp.status_code == 200
    assert resp.json()["profile_visible"] is True  # public by default (9 Jul 2026)


async def test_update_me_partial_patch(client):
    await client.post("/auth/bootstrap")
    resp = await client.patch("/me", json={"full_name": "Shamshi K", "library_visible": True})
    assert resp.status_code == 200
    body = resp.json()
    assert body["full_name"] == "Shamshi K"
    assert body["library_visible"] is True
    assert body["profile_visible"] is True  # untouched fields stay put


async def test_set_username_lowercases_and_shows_on_me(client):
    await client.post("/auth/bootstrap")
    resp = await client.patch("/me", json={"username": "ShamShi_K"})
    assert resp.status_code == 200
    assert resp.json()["username"] == "shamshi_k"
    assert (await client.get("/me")).json()["username"] == "shamshi_k"


async def test_delete_then_rebootstrap_revives_profile(client):
    # Re-created account (same auth user): delete soft-deletes the profile; the
    # next bootstrap must revive it so the reader can get back in.
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"preferred_languages": ["Malayalam"]})
    assert (await client.delete("/me")).status_code == 204
    assert (await client.get("/me")).status_code == 404  # deleted
    # Sign in again → bootstrap revives it.
    await client.post("/auth/bootstrap")
    resp = await client.get("/me")
    assert resp.status_code == 200
    # And it's writable again (this is what was failing at the language step).
    assert (await client.patch("/me", json={"preferred_languages": ["English"]})).status_code == 200


async def test_preferred_languages_default_empty_then_set(client):
    await client.post("/auth/bootstrap")
    assert (await client.get("/me")).json()["preferred_languages"] == []
    # Set, with dedupe + blank-trimming applied.
    resp = await client.patch(
        "/me", json={"preferred_languages": ["Malayalam", "English", "Malayalam", " "]}
    )
    assert resp.status_code == 200
    assert resp.json()["preferred_languages"] == ["Malayalam", "English"]
    assert (await client.get("/me")).json()["preferred_languages"] == ["Malayalam", "English"]


async def test_username_validation_rejects_bad_handles(client):
    await client.post("/auth/bootstrap")
    for bad in ["ab", "1nope", "has space", "waytoolongusername1234"]:
        resp = await client.patch("/me", json={"username": bad})
        assert resp.status_code == 422, bad


async def test_username_conflict_returns_409(client, db_sessionmaker):
    import uuid

    from app.models.profile import Profile

    await client.post("/auth/bootstrap")
    async with db_sessionmaker() as s:
        s.add(Profile(id=uuid.uuid4(), email="other@example.com", username="taken"))
        await s.commit()

    resp = await client.patch("/me", json={"username": "Taken"})  # case-insensitive collision
    assert resp.status_code == 409
    assert resp.json()["code"] == "username_taken"


async def test_username_availability(client, db_sessionmaker):
    import uuid

    from app.models.profile import Profile

    await client.post("/auth/bootstrap")
    async with db_sessionmaker() as s:
        s.add(Profile(id=uuid.uuid4(), email="other@example.com", username="reader42"))
        await s.commit()

    taken = await client.get("/me/username-available", params={"username": "reader42"})
    assert taken.json()["available"] is False
    free = await client.get("/me/username-available", params={"username": "freehandle"})
    assert free.json()["available"] is True
    bad = await client.get("/me/username-available", params={"username": "!!"})
    assert bad.json()["available"] is False  # malformed → unavailable, not a 422


async def test_user_search_finds_users_with_username(client, db_sessionmaker):
    import uuid

    from app.models.profile import Profile

    await client.post("/auth/bootstrap")
    async with db_sessionmaker() as s:
        s.add(Profile(id=uuid.uuid4(), email="a@example.com", username="bookworm"))
        s.add(Profile(id=uuid.uuid4(), email="b@example.com", username="bibliophile"))
        await s.commit()

    resp = await client.get("/users/search", params={"q": "book"})
    assert resp.status_code == 200
    handles = [u["username"] for u in resp.json()]
    assert "bookworm" in handles
    assert "bibliophile" not in handles  # prefix match only


async def test_score_reflects_contributions(client):
    await client.post("/auth/bootstrap")
    # A fresh reader has no points.
    assert (await client.get("/me/score")).json()["total"] == 0

    await client.post("/catalog/works", json={"title": "My First Book"})
    await client.post("/catalog/authors", json={"name": "A Contributed Author"})

    score = (await client.get("/me/score")).json()
    assert score["books_added"] == 1
    assert score["authors_added"] == 1
    assert score["total"] == 10 + 5  # book (10) + author (5)
    # /me carries the same total.
    assert (await client.get("/me")).json()["score"] == 15


async def test_delete_me_soft_deletes(client):
    await client.post("/auth/bootstrap")
    resp = await client.delete("/me")
    assert resp.status_code == 204

    follow_up = await client.get("/me")
    assert follow_up.status_code == 404


# --- bootstrap converges provider-owned fields (owner report, 31 Jul 2026) ---
#
# Bootstrap runs on every launch with a session, so it has to converge rather
# than no-op when the row exists. Apple gives no picture and often no name on
# first sign-in; a later sign-in enriches the Supabase identity, and the old
# early-return left the profile showing a raw email and a monogram forever.


async def test_bootstrap_backfills_a_name_and_avatar_it_didnt_have(client, user):
    # First sign-in: the provider told us nothing but the email.
    await client.post("/auth/bootstrap")
    body = (await client.get("/me")).json()
    assert body["full_name"] is None
    assert body["avatar_url"] is None

    # A later sign-in carries the enriched identity.
    user["full_name"] = "Shamsheer AT"
    user["avatar_url"] = "https://example.com/a.jpg"
    await client.post("/auth/bootstrap")

    body = (await client.get("/me")).json()
    assert body["full_name"] == "Shamsheer AT"
    assert body["avatar_url"] == "https://example.com/a.jpg"


async def test_bootstrap_never_overwrites_a_name_the_reader_edited(client, user):
    """full_name is editable in the app — a provider must not stomp it on
    every launch. avatar_url has no in-app editor, so it still refreshes."""
    user["full_name"] = "Shamsheer AT"
    user["avatar_url"] = "https://example.com/old.jpg"
    await client.post("/auth/bootstrap")

    await client.patch("/me", json={"full_name": "Shamshi"})

    user["full_name"] = "Shamsheer AT"  # provider still says the formal name
    user["avatar_url"] = "https://example.com/new.jpg"  # …and rotated the URL
    await client.post("/auth/bootstrap")

    body = (await client.get("/me")).json()
    assert body["full_name"] == "Shamshi"
    assert body["avatar_url"] == "https://example.com/new.jpg"


async def test_bootstrap_keeps_the_email_in_step(client, user):
    await client.post("/auth/bootstrap")
    user["email"] = "moved@example.com"
    await client.post("/auth/bootstrap")
    assert (await client.get("/me")).json()["email"] == "moved@example.com"
