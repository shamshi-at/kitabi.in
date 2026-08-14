"""The live reading sitting, shared across one reader's devices.

Owner request (14 Aug 2026): the same account on two phones should share one
running timer — start it on either, see and stop it on the other.

What these pin down is mostly *not* the happy path: it's the rules that keep a
running timer from being lost or double-logged, since a reader in the middle of
a sitting is the worst possible person to lose data from.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest


def _payload(**over) -> dict:
    base = {
        "session_id": str(uuid.uuid4()),
        "library_entry_id": str(uuid.uuid4()),
        "started_at": datetime.now(UTC).isoformat(),
        "page_start": 88,
        "device_id": "phone-a",
    }
    base.update(over)
    return base


@pytest.mark.anyio
async def test_nothing_running_is_null_not_404(client):
    """A quiet account is a normal answer, not an error — the app calls this on
    every foreground and must not treat "no timer" as a failure to retry."""
    res = await client.get("/reading/active")
    assert res.status_code == 200
    assert res.json() is None


@pytest.mark.anyio
async def test_start_then_read_it_back(client):
    body = _payload()
    res = await client.put("/reading/active", json=body)
    assert res.status_code == 200

    got = (await client.get("/reading/active")).json()
    assert got["session_id"] == body["session_id"]
    assert got["library_entry_id"] == body["library_entry_id"]
    assert got["page_start"] == 88
    # Echoed so the originating install can ignore its own push.
    assert got["device_id"] == "phone-a"


@pytest.mark.anyio
async def test_one_live_sitting_per_account(client):
    """Starting anywhere replaces whatever was running — the same rule the app
    already applies on a single device, now true across devices."""
    first = _payload(device_id="phone-a")
    second = _payload(device_id="phone-b")
    await client.put("/reading/active", json=first)
    await client.put("/reading/active", json=second)

    got = (await client.get("/reading/active")).json()
    assert got["session_id"] == second["session_id"]
    assert got["device_id"] == "phone-b"


@pytest.mark.anyio
async def test_restarting_the_same_sitting_is_idempotent(client):
    """The app re-sends this on foreground and after a check-in, so it doubles
    as "refresh what the other devices know"."""
    body = _payload()
    await client.put("/reading/active", json=body)

    confirmed = datetime.now(UTC)
    body["confirmed_at"] = confirmed.isoformat()
    await client.put("/reading/active", json=body)

    got = (await client.get("/reading/active")).json()
    assert got["session_id"] == body["session_id"]
    assert got["confirmed_at"] is not None


@pytest.mark.anyio
async def test_stop_from_the_other_device(client):
    await client.put("/reading/active", json=_payload(device_id="phone-a"))

    res = await client.delete("/reading/active", params={"device_id": "phone-b"})
    assert res.status_code == 204
    assert (await client.get("/reading/active")).json() is None


@pytest.mark.anyio
async def test_stopping_twice_is_not_an_error(client):
    """Both devices can race to stop the same sitting — the reader taps one,
    then picks up the other. The loser must not see a failure for doing the
    thing that already happened."""
    await client.put("/reading/active", json=_payload())
    assert (await client.delete("/reading/active")).status_code == 204
    assert (await client.delete("/reading/active")).status_code == 204


@pytest.mark.anyio
async def test_the_session_id_is_the_clients(client):
    """Rule 4: the server never assigns ids to syncable entities. The finished
    reading_sessions row reuses this id, which is exactly what stops two
    devices producing two rows for one sitting."""
    mine = str(uuid.uuid4())
    await client.put("/reading/active", json=_payload(session_id=mine))
    assert (await client.get("/reading/active")).json()["session_id"] == mine


@pytest.mark.anyio
async def test_started_at_survives_the_round_trip(client):
    """The second device renders a clock from this: a shifted timestamp is a
    visibly wrong elapsed time, not a subtle bug."""
    started = datetime.now(UTC) - timedelta(minutes=42)
    await client.put("/reading/active", json=_payload(started_at=started.isoformat()))

    got = (await client.get("/reading/active")).json()
    assert abs((datetime.fromisoformat(got["started_at"]) - started).total_seconds()) < 1
