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


async def test_tokens_exclude_the_originating_device(db_sessionmaker, user):
    """Owner report (14 Aug 2026): starting a sitting banner-ed the very device
    that started it. A visible notification is drawn by the OS before any app
    code runs, so "the app ignores its own event" cannot work — the originating
    install has to be left out of the fan-out here.

    By device, not by token: one install holds several tokens over its life."""
    uid = uuid.UUID(user["id"])
    async with db_sessionmaker() as db:
        await device_service.register(db, uid, "old-tok", "ios", device_id="phone-a")
        await device_service.register(db, uid, "new-tok", "ios", device_id="phone-a")
        await device_service.register(db, uid, "other", "android", device_id="phone-b")
        tokens = await device_service.tokens_for_user(db, uid, exclude_device_id="phone-a")
    assert tokens == ["other"]


async def test_a_token_with_no_device_id_still_receives(db_sessionmaker, user):
    """An older build registered no device id. `!=` would compare NULL and drop
    the row from *every* fan-out — losing pushes to a device that is not even
    the one being excluded. NULL means "some other device"."""
    uid = uuid.UUID(user["id"])
    async with db_sessionmaker() as db:
        await device_service.register(db, uid, "legacy", "android")
        tokens = await device_service.tokens_for_user(db, uid, exclude_device_id="phone-a")
    assert tokens == ["legacy"]


async def test_reregistering_without_a_device_id_does_not_blank_it(db_sessionmaker, user):
    """The reader's two devices may be on different builds; the newer one must
    not lose its exclusion because the token was re-registered by the older."""
    uid = uuid.UUID(user["id"])
    async with db_sessionmaker() as db:
        await device_service.register(db, uid, "tok", "ios", device_id="phone-a")
        await device_service.register(db, uid, "tok", "ios")
        assert await device_service.tokens_for_user(db, uid, exclude_device_id="phone-a") == []


async def test_register_and_unregister_endpoints(client):
    assert (
        await client.post(
            "/devices", json={"token": "t1", "platform": "ios", "device_id": "phone-a"}
        )
    ).status_code == 204
    # DELETE carries a body — use request() since httpx.delete() takes no json.
    assert (await client.request("DELETE", "/devices", json={"token": "t1"})).status_code == 204


async def test_push_is_a_noop_when_unconfigured():
    # No FIREBASE_CREDENTIALS in the test env → push_enabled is False, so these
    # return immediately without opening a session or hitting the network.
    await push_service.notify_connection_request(uuid.uuid4(), uuid.uuid4())
    await push_service.notify_connection_accepted(uuid.uuid4(), uuid.uuid4())
