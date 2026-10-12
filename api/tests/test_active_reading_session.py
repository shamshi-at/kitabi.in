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


# --- The sweeper: a sitting whose device never comes back ------------------
#
# Owner report, 12 Oct 2026: two sittings had been "Reading now" in the console
# for a month. Only a device's DELETE removes the row, and a phone that
# auto-stopped in the background and was never opened again never sends it.


async def _seed(db_sessionmaker, *, started_ago, confirmed_ago=None):
    from app.schemas.reading import ActiveSessionIn
    from app.services import active_session_service

    now = datetime.now(UTC)
    user_id = uuid.uuid4()
    body = _payload(started_at=(now - started_ago).isoformat())
    if confirmed_ago is not None:
        body["confirmed_at"] = (now - confirmed_ago).isoformat()
    async with db_sessionmaker() as db:
        await active_session_service.start(db, user_id, ActiveSessionIn(**body))
    return user_id


async def _running(db_sessionmaker) -> set:
    from sqlalchemy import select

    from app.models.active_reading_session import ActiveReadingSession

    async with db_sessionmaker() as db:
        return set((await db.execute(select(ActiveReadingSession.user_id))).scalars())


@pytest.mark.anyio
async def test_the_sweep_takes_down_a_sitting_abandoned_for_a_day(db_sessionmaker):
    from app.services import active_session_service

    abandoned = await _seed(db_sessionmaker, started_ago=timedelta(days=30))
    reading = await _seed(db_sessionmaker, started_ago=timedelta(minutes=20))

    async with db_sessionmaker() as db:
        swept = await active_session_service.sweep_stale(db, datetime.now(UTC))

    assert [r.user_id for r in swept] == [abandoned]
    assert await _running(db_sessionmaker) == {reading}


@pytest.mark.anyio
async def test_the_sweep_never_cuts_short_a_sitting_the_app_would_still_run(db_sessionmaker):
    """The app's longest deadline is 240 + 30 minutes after the start. Nothing
    a device could still be timing may be swept — the margin is the point."""
    from app.services import active_session_service

    longest = await _seed(db_sessionmaker, started_ago=timedelta(hours=5))
    async with db_sessionmaker() as db:
        assert await active_session_service.sweep_stale(db, datetime.now(UTC)) == []
    assert await _running(db_sessionmaker) == {longest}


@pytest.mark.anyio
async def test_a_still_reading_answer_moves_the_sweep_too(db_sessionmaker):
    """Same rule as the app's deadline (the 26 Jul lesson): a confirmation
    counts as a sign of life for every mechanism, the server's included."""
    from app.services import active_session_service

    confirmed = await _seed(
        db_sessionmaker, started_ago=timedelta(hours=30), confirmed_ago=timedelta(hours=2)
    )
    stale = await _seed(
        db_sessionmaker, started_ago=timedelta(hours=60), confirmed_ago=timedelta(hours=30)
    )
    async with db_sessionmaker() as db:
        swept = await active_session_service.sweep_stale(db, datetime.now(UTC))

    assert [r.user_id for r in swept] == [stale]
    assert await _running(db_sessionmaker) == {confirmed}


@pytest.mark.anyio
async def test_the_sweep_job_runs_against_the_database(db_sessionmaker, monkeypatch):
    """Through the scheduled entry point, so the job and its lock are exercised
    — a sweeper that exists but is never called is how this bug happened."""
    from app.jobs import sweep_active_sessions as job

    stopped = []

    async def fake_stop(user_id, *, session_id, device_id):
        stopped.append((user_id, device_id))

    monkeypatch.setattr(job, "SessionLocal", db_sessionmaker)
    monkeypatch.setattr(job.push_service, "notify_reading_stopped", fake_stop)

    abandoned = await _seed(db_sessionmaker, started_ago=timedelta(days=2))
    await job.sweep_active_sessions()

    assert await _running(db_sessionmaker) == set()
    # To every device on the account, the one that held the sitting included.
    assert stopped == [(abandoned, None)]


def test_the_sweep_is_scheduled(monkeypatch):
    from app.jobs import scheduler

    monkeypatch.setattr(scheduler.scheduler, "start", lambda: None)
    scheduler.start()
    try:
        assert scheduler.scheduler.get_job("sweep_active_sessions") is not None
    finally:
        scheduler.scheduler.remove_all_jobs()
