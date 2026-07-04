async def test_get_me_requires_bootstrap(client):
    resp = await client.get("/me")
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_bootstrapped"


async def test_get_me_after_bootstrap(client):
    await client.post("/auth/bootstrap")
    resp = await client.get("/me")
    assert resp.status_code == 200
    assert resp.json()["profile_visible"] is False


async def test_update_me_partial_patch(client):
    await client.post("/auth/bootstrap")
    resp = await client.patch("/me", json={"full_name": "Shamshi K", "library_visible": True})
    assert resp.status_code == 200
    body = resp.json()
    assert body["full_name"] == "Shamshi K"
    assert body["library_visible"] is True
    assert body["profile_visible"] is False  # untouched fields stay put


async def test_delete_me_soft_deletes(client):
    await client.post("/auth/bootstrap")
    resp = await client.delete("/me")
    assert resp.status_code == 204

    follow_up = await client.get("/me")
    assert follow_up.status_code == 404
