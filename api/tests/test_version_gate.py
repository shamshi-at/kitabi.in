from app.core.version_gate import parse_version


def test_parse_version():
    assert parse_version("1.2.3") == (1, 2, 3)
    assert parse_version("0.1.0") == (0, 1, 0)
    assert parse_version("v2.0") == (2, 0)
    assert parse_version("garbage") == (0,)
    assert parse_version("1.2.0") > parse_version("1.1.9")


async def test_old_app_version_is_gated(client):
    resp = await client.get("/catalog/search?q=x", headers={"X-App-Version": "0.0.1"})
    assert resp.status_code == 426
    body = resp.json()
    assert body["code"] == "update_required"
    assert body["min_version"] == "0.1.0"


async def test_current_app_version_passes(client):
    resp = await client.get("/catalog/search?q=nothing", headers={"X-App-Version": "0.1.0"})
    assert resp.status_code == 200


async def test_no_version_header_is_allowed(client):
    # curl / web docs send no header — not gated.
    resp = await client.get("/catalog/search?q=nothing")
    assert resp.status_code == 200


async def test_healthz_is_never_gated(client):
    resp = await client.get("/healthz", headers={"X-App-Version": "0.0.1"})
    assert resp.status_code == 200
