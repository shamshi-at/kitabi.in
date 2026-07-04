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
