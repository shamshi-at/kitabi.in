import uuid

from sqlalchemy import text

DEVICE_A = str(uuid.uuid4())
DEVICE_B = str(uuid.uuid4())


async def _seed_edition(client) -> tuple[str, str]:
    """Returns (work_id, edition_id) for a freshly created catalog entry."""
    resp = await client.post("/catalog/works", json={"title": "Aadujeevitham"})
    body = resp.json()
    return body["id"], body["editions"][0]["id"]


def _op(entity: str, entity_id: str, op_type: str, payload: dict, device: str = DEVICE_A) -> dict:
    return {
        "op_id": str(uuid.uuid4()),
        "device_id": device,
        "entity": entity,
        "entity_id": entity_id,
        "op_type": op_type,
        "payload": payload,
    }


async def test_push_create_library_entry(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    op = _op("library_entries", entry_id, "create", {"edition_id": edition_id, "status": "reading"})

    resp = await client.post("/sync/push", json={"ops": [op]})
    assert resp.status_code == 200
    results = resp.json()["results"]
    assert results[0]["status"] == "applied"
    assert results[0]["server_seq"] is not None


async def test_push_is_idempotent_on_replay(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    op = _op("library_entries", entry_id, "create", {"edition_id": edition_id})

    first = await client.post("/sync/push", json={"ops": [op]})
    second = await client.post("/sync/push", json={"ops": [op]})

    assert first.json()["results"][0]["status"] == "applied"
    assert second.json()["results"][0]["status"] == "duplicate"


async def test_push_update_after_create(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    update = _op("library_entries", entry_id, "update", {"status": "read", "current_page": 250})

    resp = await client.post("/sync/push", json={"ops": [create, update]})
    results = resp.json()["results"]
    assert results[0]["status"] == "applied"
    assert results[1]["status"] == "applied"
    assert results[1]["server_seq"] > results[0]["server_seq"]


async def test_delete_wins_rejects_later_update(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    delete = _op("library_entries", entry_id, "delete", {})
    update = _op("library_entries", entry_id, "update", {"status": "read"})

    resp = await client.post("/sync/push", json={"ops": [create, delete, update]})
    results = resp.json()["results"]
    assert results[1]["status"] == "applied"  # delete
    assert results[2]["status"] == "rejected"
    assert results[2]["code"] == "deleted_wins"


async def test_delete_wins_writes_conflict_history(client, db_sessionmaker):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    delete = _op("library_entries", entry_id, "delete", {})
    update = _op("library_entries", entry_id, "update", {"status": "read"})
    await client.post("/sync/push", json={"ops": [create, delete, update]})

    async with db_sessionmaker() as session:
        rows = (
            await session.execute(
                text("SELECT rule FROM conflict_history WHERE entity_id = :id"), {"id": entry_id}
            )
        ).all()
    assert [r[0] for r in rows] == ["delete_wins"]


async def test_last_write_wins_applies_and_logs_conflict(client, db_sessionmaker):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op("library_entries", entry_id, "create", {"edition_id": edition_id}, DEVICE_A)
    update_a = _op("library_entries", entry_id, "update", {"notes": "from phone"}, DEVICE_A)
    update_b = _op("library_entries", entry_id, "update", {"notes": "from tablet"}, DEVICE_B)

    await client.post("/sync/push", json={"ops": [create, update_a]})
    resp = await client.post("/sync/push", json={"ops": [update_b]})

    # A different device's update still applies (server-received order wins)...
    assert resp.json()["results"][0]["status"] == "applied"

    # ...but the disagreement is logged, not resolved silently.
    async with db_sessionmaker() as session:
        rows = (
            await session.execute(
                text("SELECT rule FROM conflict_history WHERE entity_id = :id"), {"id": entry_id}
            )
        ).all()
    assert [r[0] for r in rows] == ["last_write_wins"]


async def test_conflict_on_row_with_date_columns_serializes(client, db_sessionmaker):
    """The discarded payload snapshots the whole row — plain `date` columns
    (start_date, lent_date…) must serialize into the JSONB conflict row, or the
    entire push batch 500s. Regression: cross-device update on a dated row."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op(
        "library_entries",
        entry_id,
        "create",
        {"edition_id": edition_id, "start_date": "2026-07-01"},
        DEVICE_A,
    )
    update = _op("library_entries", entry_id, "update", {"status": "read"}, DEVICE_B)

    await client.post("/sync/push", json={"ops": [create]})
    resp = await client.post("/sync/push", json={"ops": [update]})

    assert resp.status_code == 200
    assert resp.json()["results"][0]["status"] == "applied"
    async with db_sessionmaker() as session:
        rows = (
            await session.execute(
                text("SELECT rule FROM conflict_history WHERE entity_id = :id"), {"id": entry_id}
            )
        ).all()
    assert [r[0] for r in rows] == ["last_write_wins"]


async def test_create_referencing_another_users_entry_is_rejected(client, db_sessionmaker, user_b):
    """The FK only proves the referenced row exists — a lending record hung off
    ANOTHER user's library entry must be rejected, not applied."""
    import uuid as _uuid

    _, edition_id = await _seed_edition(client)
    foreign_entry = str(_uuid.uuid4())
    async with db_sessionmaker() as session:
        await session.execute(
            text(
                "INSERT INTO library_entries (id, user_id, edition_id, status, is_favorite,"
                " created_at, updated_at) VALUES (:id, :uid, :ed, 'pending', false, now(), now())"
            ),
            {"id": foreign_entry, "uid": user_b["id"], "ed": edition_id},
        )
        await session.commit()

    op = _op(
        "lending_records",
        str(_uuid.uuid4()),
        "create",
        {
            "direction": "lent",
            "library_entry_id": foreign_entry,
            "borrower_name": "Mallory",
            "lent_date": "2026-07-01",
        },
    )
    resp = await client.post("/sync/push", json={"ops": [op]})
    result = resp.json()["results"][0]
    assert result["status"] == "rejected"
    assert result["code"] == "invalid_reference"


async def test_same_device_updates_do_not_conflict(client, db_sessionmaker):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op("library_entries", entry_id, "create", {"edition_id": edition_id}, DEVICE_A)
    update1 = _op("library_entries", entry_id, "update", {"current_page": 10}, DEVICE_A)
    update2 = _op("library_entries", entry_id, "update", {"current_page": 20}, DEVICE_A)
    await client.post("/sync/push", json={"ops": [create, update1, update2]})

    async with db_sessionmaker() as session:
        rows = (
            await session.execute(
                text("SELECT rule FROM conflict_history WHERE entity_id = :id"), {"id": entry_id}
            )
        ).all()
    assert rows == []


async def test_push_rejects_invalid_reference(client):
    entry_id = str(uuid.uuid4())
    op = _op("library_entries", entry_id, "create", {"edition_id": str(uuid.uuid4())})

    resp = await client.post("/sync/push", json={"ops": [op]})
    result = resp.json()["results"][0]
    assert result["status"] == "rejected"
    assert result["code"] == "invalid_reference"


async def test_push_rejects_invalid_payload(client):
    work_id, _ = await _seed_edition(client)
    op = _op("ratings", str(uuid.uuid4()), "create", {"work_id": work_id, "value": 9})

    resp = await client.post("/sync/push", json={"ops": [op]})
    result = resp.json()["results"][0]
    assert result["status"] == "rejected"
    assert result["code"] == "invalid_payload"


async def test_pull_returns_changes_since_cursor(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    await client.post(
        "/sync/push",
        json={"ops": [_op("library_entries", entry_id, "create", {"edition_id": edition_id})]},
    )

    first = await client.get("/sync/pull", params={"cursor": 0})
    body = first.json()
    assert any(
        c["entity"] == "library_entries" and c["data"]["id"] == entry_id for c in body["changes"]
    )
    assert body["has_more"] is False

    second = await client.get("/sync/pull", params={"cursor": body["next_cursor"]})
    assert second.json()["changes"] == []


async def test_pull_includes_activity_log_side_effect(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    await client.post(
        "/sync/push",
        json={"ops": [_op("library_entries", entry_id, "create", {"edition_id": edition_id})]},
    )

    pulled = (await client.get("/sync/pull", params={"cursor": 0})).json()
    activity = [c for c in pulled["changes"] if c["entity"] == "activity_log_entries"]
    assert len(activity) == 1
    assert activity[0]["data"]["event_type"] == "added_book"


async def test_finishing_a_book_logs_activity(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op(
        "library_entries", entry_id, "create", {"edition_id": edition_id, "status": "reading"}
    )
    finish = _op("library_entries", entry_id, "update", {"status": "read"})
    await client.post("/sync/push", json={"ops": [create, finish]})

    pulled = (await client.get("/sync/pull", params={"cursor": 0})).json()
    events = [
        c["data"]["event_type"] for c in pulled["changes"] if c["entity"] == "activity_log_entries"
    ]
    assert "added_book" in events
    assert "finished_book" in events


async def test_rating_and_review_and_tag_and_lending_flow(client):
    work_id, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    tag_id = str(uuid.uuid4())

    ops = [
        _op("library_entries", entry_id, "create", {"edition_id": edition_id}),
        _op("ratings", str(uuid.uuid4()), "create", {"work_id": work_id, "value": 5}),
        _op("reviews", str(uuid.uuid4()), "create", {"work_id": work_id, "body": "Loved it."}),
        _op("personal_tags", tag_id, "create", {"name": "beach reads"}),
        _op(
            "library_entry_tags",
            str(uuid.uuid4()),
            "create",
            {"library_entry_id": entry_id, "tag_id": tag_id},
        ),
        _op(
            "lending_records",
            str(uuid.uuid4()),
            "create",
            {
                "library_entry_id": entry_id,
                "borrower_name": "Anu",
                "lent_date": "2026-07-01",
            },
        ),
    ]
    resp = await client.post("/sync/push", json={"ops": ops})
    statuses = [r["status"] for r in resp.json()["results"]]
    assert statuses == ["applied"] * len(ops)


async def test_push_borrowed_lending_record_without_library_entry(client):
    """A borrowed record has no owned library entry — it points at the catalog
    edition instead, with direction='borrowed' and an optional note."""
    _, edition_id = await _seed_edition(client)
    record_id = str(uuid.uuid4())
    op = _op(
        "lending_records",
        record_id,
        "create",
        {
            "direction": "borrowed",
            "edition_id": edition_id,
            "borrower_name": "Divya",
            "lent_date": "2026-07-02",
            "note": "Handle with care",
        },
    )
    resp = await client.post("/sync/push", json={"ops": [op]})
    assert resp.json()["results"][0]["status"] == "applied"

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    record = next(c for c in pulled.json()["changes"] if c["entity"] == "lending_records")
    assert record["data"]["direction"] == "borrowed"
    assert record["data"]["edition_id"] == edition_id
    assert record["data"]["library_entry_id"] is None
    assert record["data"]["note"] == "Handle with care"


async def test_library_entry_defaults_to_owned(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    op = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    await client.post("/sync/push", json={"ops": [op]})

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    entry = next(c for c in pulled.json()["changes"] if c["data"]["id"] == entry_id)
    assert entry["data"]["ownership"] == "owned"


async def test_borrowed_library_entry_links_back_from_lending_record(client):
    """The unified borrow flow (owner request, 15 Jul 2026): a borrowed book
    gets a real library_entries row (ownership='borrowed') that the lending
    record's library_entry_id points at — so status/progress work on it like
    any owned book, and it isn't a bare lending_records row anymore."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    record_id = str(uuid.uuid4())

    ops = [
        _op(
            "library_entries",
            entry_id,
            "create",
            {"edition_id": edition_id, "status": "reading", "ownership": "borrowed"},
        ),
        _op(
            "lending_records",
            record_id,
            "create",
            {
                "direction": "borrowed",
                "library_entry_id": entry_id,
                "edition_id": edition_id,
                "borrower_name": "Divya",
                "lent_date": "2026-07-15",
            },
        ),
    ]
    resp = await client.post("/sync/push", json={"ops": ops})
    assert [r["status"] for r in resp.json()["results"]] == ["applied", "applied"]

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    changes = pulled.json()["changes"]
    entry = next(
        c for c in changes if c["entity"] == "library_entries" and c["data"]["id"] == entry_id
    )
    record = next(
        c for c in changes if c["entity"] == "lending_records" and c["data"]["id"] == record_id
    )
    assert entry["data"]["ownership"] == "borrowed"
    assert entry["data"]["status"] == "reading"
    assert record["data"]["library_entry_id"] == entry_id


async def test_returning_a_loan_does_not_touch_the_library_entry(client):
    """Returning a borrow must never delete/hide the shelf entry — "returned"
    lives only on the lending record; the reader keeps reading status,
    progress, and notes on the entry either side of the return."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    record_id = str(uuid.uuid4())

    ops = [
        _op(
            "library_entries",
            entry_id,
            "create",
            {"edition_id": edition_id, "status": "read", "ownership": "borrowed"},
        ),
        _op(
            "lending_records",
            record_id,
            "create",
            {
                "direction": "borrowed",
                "library_entry_id": entry_id,
                "edition_id": edition_id,
                "borrower_name": "Divya",
                "lent_date": "2026-07-01",
            },
        ),
    ]
    await client.post("/sync/push", json={"ops": ops})
    returned = _op("lending_records", record_id, "update", {"returned_date": "2026-07-15"})
    resp = await client.post("/sync/push", json={"ops": [returned]})
    assert resp.json()["results"][0]["status"] == "applied"

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    changes = pulled.json()["changes"]
    entry = next(
        c for c in changes if c["entity"] == "library_entries" and c["data"]["id"] == entry_id
    )
    record = next(
        c for c in changes if c["entity"] == "lending_records" and c["data"]["id"] == record_id
    )
    assert entry["data"]["deleted_at"] is None
    assert entry["data"]["ownership"] == "borrowed"
    assert entry["data"]["status"] == "read"
    assert record["data"]["returned_date"] == "2026-07-15"


async def test_buying_a_borrowed_book_flips_ownership_and_keeps_the_lending_log(client):
    """The "I bought this" transition: ownership flips to 'owned' on the same
    row (same id — reading history untouched); the LendingRecord (the loan
    log) is never modified or deleted, so the borrow is still on record."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    record_id = str(uuid.uuid4())

    ops = [
        _op(
            "library_entries",
            entry_id,
            "create",
            {"edition_id": edition_id, "status": "read", "ownership": "borrowed"},
        ),
        _op(
            "lending_records",
            record_id,
            "create",
            {
                "direction": "borrowed",
                "library_entry_id": entry_id,
                "edition_id": edition_id,
                "borrower_name": "Divya",
                "lent_date": "2026-07-01",
                "returned_date": "2026-07-10",
            },
        ),
    ]
    await client.post("/sync/push", json={"ops": ops})
    buy = _op("library_entries", entry_id, "update", {"ownership": "owned"})
    resp = await client.post("/sync/push", json={"ops": [buy]})
    assert resp.json()["results"][0]["status"] == "applied"

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    changes = pulled.json()["changes"]
    entry = next(
        c for c in changes if c["entity"] == "library_entries" and c["data"]["id"] == entry_id
    )
    record = next(
        c for c in changes if c["entity"] == "lending_records" and c["data"]["id"] == record_id
    )
    assert entry["data"]["ownership"] == "owned"
    assert entry["data"]["status"] == "read"  # untouched by the ownership flip
    assert record["data"]["returned_date"] == "2026-07-10"  # the log survives intact
    assert record["data"]["library_entry_id"] == entry_id


async def test_delete_op_carries_empty_payload_and_is_idempotent(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    create = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    delete = _op("library_entries", entry_id, "delete", {})
    await client.post("/sync/push", json={"ops": [create]})

    first = await client.post("/sync/push", json={"ops": [delete]})
    second = await client.post("/sync/push", json={"ops": [delete]})
    assert first.json()["results"][0]["status"] == "applied"
    assert second.json()["results"][0]["status"] == "duplicate"


async def test_push_reading_session_and_pull_reflects_it(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    entry_op = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    session_id = str(uuid.uuid4())
    session_op = _op(
        "reading_sessions",
        session_id,
        "create",
        {
            "library_entry_id": entry_id,
            "started_at": "2026-07-10T20:00:00Z",
            "ended_at": "2026-07-10T20:24:00Z",
            "duration_seconds": 1440,
            "page_start": 184,
            "page_end": 196,
        },
    )
    resp = await client.post("/sync/push", json={"ops": [entry_op, session_op]})
    results = resp.json()["results"]
    assert results[0]["status"] == "applied"
    assert results[1]["status"] == "applied"

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    session = next(c for c in pulled.json()["changes"] if c["entity"] == "reading_sessions")
    assert session["data"]["library_entry_id"] == entry_id
    assert session["data"]["duration_seconds"] == 1440
    assert session["data"]["page_start"] == 184
    assert session["data"]["page_end"] == 196


async def test_reading_session_referencing_another_users_entry_is_rejected(
    client, db_sessionmaker, user_b
):
    """Same rule as lending_records — the FK only proves the row exists, not
    that the pusher owns it."""
    import uuid as _uuid

    _, edition_id = await _seed_edition(client)
    foreign_entry = str(_uuid.uuid4())
    async with db_sessionmaker() as session:
        await session.execute(
            text(
                "INSERT INTO library_entries (id, user_id, edition_id, status, is_favorite,"
                " created_at, updated_at) VALUES (:id, :uid, :ed, 'pending', false, now(), now())"
            ),
            {"id": foreign_entry, "uid": user_b["id"], "ed": edition_id},
        )
        await session.commit()

    op = _op(
        "reading_sessions",
        str(_uuid.uuid4()),
        "create",
        {
            "library_entry_id": foreign_entry,
            "started_at": "2026-07-10T20:00:00Z",
            "ended_at": "2026-07-10T20:10:00Z",
            "duration_seconds": 600,
        },
    )
    resp = await client.post("/sync/push", json={"ops": [op]})
    result = resp.json()["results"][0]
    assert result["status"] == "rejected"
    assert result["code"] == "invalid_reference"


async def test_reading_session_update_sets_page_end(client):
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    session_id = str(uuid.uuid4())
    await client.post(
        "/sync/push",
        json={
            "ops": [
                _op("library_entries", entry_id, "create", {"edition_id": edition_id}),
                _op(
                    "reading_sessions",
                    session_id,
                    "create",
                    {
                        "library_entry_id": entry_id,
                        "started_at": "2026-07-10T20:00:00Z",
                        "ended_at": "2026-07-10T20:10:00Z",
                        "duration_seconds": 600,
                    },
                ),
            ]
        },
    )
    update = _op("reading_sessions", session_id, "update", {"page_end": 220})
    resp = await client.post("/sync/push", json={"ops": [update]})
    assert resp.json()["results"][0]["status"] == "applied"

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    session = next(c for c in pulled.json()["changes"] if c["entity"] == "reading_sessions")
    assert session["data"]["page_end"] == 220


async def test_update_can_repoint_children_at_another_owned_entry(client):
    """The client's duplicate-entry heal merges two library entries for one
    edition and re-points the loser's reading sessions / lending records at
    the keeper via plain update ops — the update schemas must accept
    library_entry_id and the server must apply it."""
    _, edition_id = await _seed_edition(client)
    keeper_id = str(uuid.uuid4())
    dup_id = str(uuid.uuid4())
    session_id = str(uuid.uuid4())
    record_id = str(uuid.uuid4())

    ops = [
        _op("library_entries", keeper_id, "create", {"edition_id": edition_id}),
        _op("library_entries", dup_id, "create", {"edition_id": edition_id}),
        _op(
            "reading_sessions",
            session_id,
            "create",
            {
                "library_entry_id": dup_id,
                "started_at": "2026-07-10T20:00:00Z",
                "ended_at": "2026-07-10T20:10:00Z",
                "duration_seconds": 600,
            },
        ),
        _op(
            "lending_records",
            record_id,
            "create",
            {"library_entry_id": dup_id, "borrower_name": "Anu", "lent_date": "2026-07-01"},
        ),
    ]
    await client.post("/sync/push", json={"ops": ops})

    heal = [
        _op("reading_sessions", session_id, "update", {"library_entry_id": keeper_id}),
        _op("lending_records", record_id, "update", {"library_entry_id": keeper_id}),
        _op("library_entries", dup_id, "delete", {}),
    ]
    resp = await client.post("/sync/push", json={"ops": heal})
    assert [r["status"] for r in resp.json()["results"]] == ["applied"] * 3

    pulled = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    session = next(c for c in pulled if c["entity"] == "reading_sessions")
    record = next(c for c in pulled if c["entity"] == "lending_records")
    dup = next(c for c in pulled if c["entity"] == "library_entries" and c["data"]["id"] == dup_id)
    assert session["data"]["library_entry_id"] == keeper_id
    assert record["data"]["library_entry_id"] == keeper_id
    assert dup["data"]["deleted_at"] is not None


async def test_update_repointing_at_another_users_entry_is_rejected(
    client, db_sessionmaker, user_b
):
    """Re-pointing on update gets the same ownership check as create — an
    update must not hang my session off another user's library entry."""
    import uuid as _uuid

    _, edition_id = await _seed_edition(client)
    entry_id = str(_uuid.uuid4())
    session_id = str(_uuid.uuid4())
    await client.post(
        "/sync/push",
        json={
            "ops": [
                _op("library_entries", entry_id, "create", {"edition_id": edition_id}),
                _op(
                    "reading_sessions",
                    session_id,
                    "create",
                    {
                        "library_entry_id": entry_id,
                        "started_at": "2026-07-10T20:00:00Z",
                        "ended_at": "2026-07-10T20:10:00Z",
                        "duration_seconds": 600,
                    },
                ),
            ]
        },
    )

    foreign_entry = str(_uuid.uuid4())
    async with db_sessionmaker() as session:
        await session.execute(
            text(
                "INSERT INTO library_entries (id, user_id, edition_id, status, is_favorite,"
                " created_at, updated_at) VALUES (:id, :uid, :ed, 'pending', false, now(), now())"
            ),
            {"id": foreign_entry, "uid": user_b["id"], "ed": edition_id},
        )
        await session.commit()

    op = _op("reading_sessions", session_id, "update", {"library_entry_id": foreign_entry})
    resp = await client.post("/sync/push", json={"ops": [op]})
    result = resp.json()["results"][0]
    assert result["status"] == "rejected"
    assert result["code"] == "invalid_reference"


async def test_push_reading_note_and_pull_reflects_it(client):
    """A note is the third Layer-2 thing hanging off a library entry, and the
    whole point of the feature is that it reaches the reader's other devices —
    so the round-trip is the test that matters."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    entry_op = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    session_id = str(uuid.uuid4())
    session_op = _op(
        "reading_sessions",
        session_id,
        "create",
        {
            "library_entry_id": entry_id,
            "started_at": "2026-07-21T20:00:00Z",
            "ended_at": "2026-07-21T20:42:00Z",
            "duration_seconds": 2520,
            "page_start": 24,
        },
    )
    note_id = str(uuid.uuid4())
    note_op = _op(
        "reading_notes",
        note_id,
        "create",
        {
            "library_entry_id": entry_id,
            "session_id": session_id,
            "body": "The Malabar sections read like memory, not plot.",
            "page_start": 24,
            "page_end": 27,
        },
    )
    resp = await client.post("/sync/push", json={"ops": [entry_op, session_op, note_op]})
    assert resp.status_code == 200, resp.text
    assert [r["status"] for r in resp.json()["results"]] == ["applied"] * 3

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    note = next(c for c in pulled.json()["changes"] if c["entity"] == "reading_notes")
    assert note["data"]["body"] == "The Malabar sections read like memory, not plot."
    assert note["data"]["session_id"] == session_id
    # The range survives — a note about a passage, not a point.
    assert note["data"]["page_start"] == 24
    assert note["data"]["page_end"] == 27


async def test_reading_note_without_a_sitting_or_pages_is_fine(client):
    """ "Lent to mom, she folds pages" belongs to the book, not to any stretch
    of reading — session and pages are all optional."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    entry_op = _op("library_entries", entry_id, "create", {"edition_id": edition_id})
    note_op = _op(
        "reading_notes",
        str(uuid.uuid4()),
        "create",
        {"library_entry_id": entry_id, "body": "Lent to mom - she folds pages."},
    )
    resp = await client.post("/sync/push", json={"ops": [entry_op, note_op]})
    assert [r["status"] for r in resp.json()["results"]] == ["applied", "applied"]

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    note = next(c for c in pulled.json()["changes"] if c["entity"] == "reading_notes")
    assert note["data"]["session_id"] is None
    assert note["data"]["page_start"] is None


async def test_reading_note_edit_and_delete_round_trip(client):
    """Editing must change the words without moving the note off its sitting,
    and a delete is a soft delete like every other Layer-2 row."""
    _, edition_id = await _seed_edition(client)
    entry_id = str(uuid.uuid4())
    note_id = str(uuid.uuid4())
    await client.post(
        "/sync/push",
        json={
            "ops": [
                _op("library_entries", entry_id, "create", {"edition_id": edition_id}),
                _op(
                    "reading_notes",
                    note_id,
                    "create",
                    {"library_entry_id": entry_id, "body": "first thought", "page_start": 22},
                ),
            ]
        },
    )

    edit = _op("reading_notes", note_id, "update", {"body": "a better thought"})
    resp = await client.post("/sync/push", json={"ops": [edit]})
    assert resp.json()["results"][0]["status"] == "applied"

    pulled = await client.get("/sync/pull", params={"cursor": 0})
    note = next(c for c in pulled.json()["changes"] if c["entity"] == "reading_notes")
    assert note["data"]["body"] == "a better thought"
    assert note["data"]["page_start"] == 22  # untouched by the edit

    delete = _op("reading_notes", note_id, "delete", {})
    resp = await client.post("/sync/push", json={"ops": [delete]})
    assert resp.json()["results"][0]["status"] == "applied"
    pulled = await client.get("/sync/pull", params={"cursor": 0})
    note = next(c for c in pulled.json()["changes"] if c["entity"] == "reading_notes")
    # Soft delete (rule 3) — the row still pulls, carrying its tombstone, so
    # every other device knows to drop it.
    assert note["data"]["deleted_at"] is not None


async def test_reading_note_on_another_users_entry_is_rejected(client, db_sessionmaker, user_b):
    """Notes are private. A crafted create must not be able to hang one off
    someone else's library entry."""
    import uuid as _uuid

    _, edition_id = await _seed_edition(client)
    foreign_entry = str(_uuid.uuid4())
    async with db_sessionmaker() as session:
        await session.execute(
            text(
                "INSERT INTO library_entries (id, user_id, edition_id, status, is_favorite,"
                " created_at, updated_at) VALUES (:id, :uid, :ed, 'pending', false, now(), now())"
            ),
            {"id": foreign_entry, "uid": user_b["id"], "ed": edition_id},
        )
        await session.commit()

    op = _op(
        "reading_notes",
        str(_uuid.uuid4()),
        "create",
        {"library_entry_id": foreign_entry, "body": "not mine to write on"},
    )
    resp = await client.post("/sync/push", json={"ops": [op]})
    result = resp.json()["results"][0]
    assert result["status"] == "rejected"
    assert result["code"] == "invalid_reference"


async def test_reading_note_citing_another_users_session_is_rejected(
    client, db_sessionmaker, user_b
):
    """The note's own entry can be legitimately owned while `session_id` points
    at a stranger's sitting — the FK proves existence, not ownership."""
    import uuid as _uuid

    _, edition_id = await _seed_edition(client)
    # A sitting belonging to user B.
    foreign_entry = str(_uuid.uuid4())
    foreign_session = str(_uuid.uuid4())
    async with db_sessionmaker() as session:
        await session.execute(
            text(
                "INSERT INTO library_entries (id, user_id, edition_id, status, is_favorite,"
                " created_at, updated_at) VALUES (:id, :uid, :ed, 'pending', false, now(), now())"
            ),
            {"id": foreign_entry, "uid": user_b["id"], "ed": edition_id},
        )
        await session.execute(
            text(
                "INSERT INTO reading_sessions (id, user_id, library_entry_id, started_at,"
                " ended_at, duration_seconds, created_at, updated_at) VALUES (:id, :uid, :entry,"
                " now(), now(), 60, now(), now())"
            ),
            {"id": foreign_session, "uid": user_b["id"], "entry": foreign_entry},
        )
        await session.commit()

    my_entry = str(_uuid.uuid4())
    ops = [
        _op("library_entries", my_entry, "create", {"edition_id": edition_id}),
        _op(
            "reading_notes",
            str(_uuid.uuid4()),
            "create",
            {"library_entry_id": my_entry, "session_id": foreign_session, "body": "hm"},
        ),
    ]
    resp = await client.post("/sync/push", json={"ops": ops})
    results = resp.json()["results"]
    assert results[0]["status"] == "applied"
    assert results[1]["status"] == "rejected"
    assert results[1]["code"] == "invalid_reference"
