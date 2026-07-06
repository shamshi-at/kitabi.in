"""Device-token registration + the push layer's dormant (unconfigured) path."""

import uuid

from app.services import device_service, push_service


async def test_register_and_list_tokens(db_sessionmaker, user):
    uid = uuid.UUID(user["id"])
    async with db_sessionmaker() as db:
        await device_service.register(db, uid, "tokA", "ios")
        await device_service.register(db, uid, "tokB", "android")
        tokens = await device_service.tokens_for_user(db, uid)
    assert set(tokens) == {"tokA", "tokB"}


async def test_register_reassigns_shared_token_to_new_user(db_sessionmaker):
    u1, u2 = uuid.uuid4(), uuid.uuid4()
    async with db_sessionmaker() as db:
        await device_service.register(db, u1, "shared", "ios")
        await device_service.register(db, u2, "shared", "ios")  # same device, new login
        assert await device_service.tokens_for_user(db, u1) == []
        assert await device_service.tokens_for_user(db, u2) == ["shared"]


async def test_prune_deletes_dead_tokens(db_sessionmaker, user):
    uid = uuid.UUID(user["id"])
    async with db_sessionmaker() as db:
        await device_service.register(db, uid, "good", "ios")
        await device_service.register(db, uid, "dead", "ios")
        await device_service.prune(db, ["dead"])
        assert await device_service.tokens_for_user(db, uid) == ["good"]


async def test_register_and_unregister_endpoints(client):
    assert (
        await client.post("/devices", json={"token": "t1", "platform": "ios"})
    ).status_code == 204
    # DELETE carries a body — use request() since httpx.delete() takes no json.
    assert (await client.request("DELETE", "/devices", json={"token": "t1"})).status_code == 204


async def test_push_is_a_noop_when_unconfigured():
    # No FIREBASE_CREDENTIALS in the test env → push_enabled is False, so these
    # return immediately without opening a session or hitting the network.
    await push_service.notify_connection_request(uuid.uuid4(), uuid.uuid4())
    await push_service.notify_connection_accepted(uuid.uuid4(), uuid.uuid4())
