async def test_bootstrap_creates_profile(client, user):
    resp = await client.post("/auth/bootstrap")
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == user["id"]
    assert body["email"] == user["email"]
    assert body["profile_visible"] is False
    assert body["library_visible"] is False
    assert body["reviews_visible_default"] is False


async def test_bootstrap_is_idempotent(client):
    first = await client.post("/auth/bootstrap")
    second = await client.post("/auth/bootstrap")
    assert first.json()["id"] == second.json()["id"]
    assert first.json()["created_at"] == second.json()["created_at"]


async def test_bootstrap_rejects_missing_token(unauthenticated_client):
    resp = await unauthenticated_client.post("/auth/bootstrap")
    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthorized"
