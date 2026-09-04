"""An ISBN the catalogue already holds.

`editions.isbn` is unique across the whole table, and nothing checked it before
the insert — so a reader adding a book whose printing was already catalogued got
a raw IntegrityError at commit, which reaches them as a 500 (owner report,
4 Sep 2026: Dharmapuranam, ISBN 9788171300662, sitting in the catalogue as a
bare OpenLibrary stub with no author, cover or page count — exactly the entry
someone wants to improve).

A taken ISBN is not an error to shrug at: it means *this exact printing is
already here*. So the answer is a 409 that names the book, the way
`GET /catalog/isbn/{isbn}` names the printing it resolved.
"""

from datetime import UTC, datetime

from app.models import Edition, Work
from app.services import catalog_service


async def _shelved(db, *, title="Dharmapuranam", isbn="9788171300662"):
    """A book already in the catalogue, holding the ISBN."""
    work = Work(title=title)
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id, isbn=isbn)
    db.add(edition)
    await db.commit()
    return work, edition


async def test_adding_a_book_whose_isbn_is_taken_is_a_409_not_a_500(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        work, edition = await _shelved(db)
        work_id, edition_id = str(work.id), str(edition.id)

    resp = await client.post(
        "/catalog/works",
        json={
            "title": "Dharmapuranam",
            "author_names": ["O. V. Vijayan"],
            "publisher_name": "DC Books",
            "language": "Malayalam",
            "isbn": "9788171300662",
            "page_count": 255,
            "format": "Paperback",
        },
    )

    assert resp.status_code == 409
    body = resp.json()
    assert body["code"] == "isbn_exists"
    # It must say WHICH book — the reader cannot work that out from the outside,
    # and the whole point is to send them to the entry they meant to improve.
    assert body["work_id"] == work_id
    assert body["edition_id"] == edition_id
    assert "Dharmapuranam" in body["message"]


async def test_the_rejected_add_leaves_no_half_made_work_behind(client, db_sessionmaker):
    """The create used to fail at commit, after the Work had been flushed. It
    rolled back then and it must still roll back now — a second Dharmapuranam
    with no edition would be worse than the 500."""
    async with db_sessionmaker() as db:
        await _shelved(db)

    await client.post(
        "/catalog/works",
        json={"title": "Dharmapuranam", "isbn": "9788171300662"},
    )

    resp = await client.get("/catalog/search?q=Dharmapuranam")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


async def test_an_isbn10_collides_with_the_isbn13_row_already_shelved(client, db_sessionmaker):
    """The two spellings are one printing. The unique index sees two different
    strings and would happily store both; `variants()` is what knows better."""
    async with db_sessionmaker() as db:
        work, _ = await _shelved(db, title="Naalukett", isbn="9788126403455")
        work_id = str(work.id)

    resp = await client.post(
        "/catalog/works",
        json={"title": "Naalukett", "isbn": "8126403454"},
    )

    assert resp.status_code == 409
    assert resp.json()["work_id"] == work_id


async def test_adding_a_printing_to_a_work_reports_the_clash_too(client, db_sessionmaker):
    """Same guard on `POST /works/{id}/editions` — a reader adding their copy to
    a book that already lists that exact printing."""
    async with db_sessionmaker() as db:
        work, edition = await _shelved(db, title="Randamoozham", isbn="9788171301234")
        other = Work(title="Randamoozham (reprint)")
        db.add(other)
        await db.flush()
        await db.commit()
        edition_id, other_id = str(edition.id), str(other.id)

    resp = await client.post(
        f"/catalog/works/{other_id}/editions",
        json={"isbn": "9788171301234", "page_count": 400},
    )

    assert resp.status_code == 409
    assert resp.json()["edition_id"] == edition_id


async def test_patching_an_edition_onto_a_taken_isbn_is_a_409(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        _, taken = await _shelved(db, title="Chemmeen", isbn="9788171302222")
        loose = Work(title="Chemmeen (another printing)")
        db.add(loose)
        await db.flush()
        mine = Edition(work_id=loose.id, isbn=None, page_count=190)
        db.add(mine)
        await db.commit()
        mine_id, taken_id = str(mine.id), str(taken.id)

    resp = await client.patch(f"/catalog/editions/{mine_id}", json={"isbn": "9788171302222"})

    assert resp.status_code == 409
    assert resp.json()["edition_id"] == taken_id


async def test_resaving_an_edition_without_changing_its_isbn_is_fine(client, db_sessionmaker):
    """The guard must not make a row conflict with itself — that would break
    every ordinary edit of a printing that has an ISBN."""
    async with db_sessionmaker() as db:
        _, edition = await _shelved(db, title="Khasakkinte Ithihasam", isbn="9788171303333")
        edition_id = str(edition.id)

    resp = await client.patch(
        f"/catalog/editions/{edition_id}",
        json={"isbn": "9788171303333", "page_count": 220},
    )

    assert resp.status_code == 200
    assert resp.json()["page_count"] == 220


async def test_a_soft_deleted_row_still_holds_the_number_and_says_so(client, db_sessionmaker):
    """`editions_isbn_key` is a plain unique index, so a soft-deleted edition
    keeps its ISBN forever and the live-rows pre-check cannot see it. The commit
    backstop catches it — and refuses to point at a book nobody can open."""
    async with db_sessionmaker() as db:
        work = Work(title="Ente Katha")
        db.add(work)
        await db.flush()
        db.add(
            Edition(
                work_id=work.id,
                isbn="9788171304444",
                deleted_at=datetime.now(UTC),
            )
        )
        await db.commit()

    resp = await client.post(
        "/catalog/works",
        json={"title": "Ente Katha", "isbn": "9788171304444"},
    )

    assert resp.status_code == 409
    body = resp.json()
    assert body["code"] == "isbn_exists"
    assert "work_id" not in body


async def test_a_book_with_no_isbn_is_never_blocked(client, db_sessionmaker):
    """Most hand-typed adds carry no ISBN at all, and any number of them must be
    allowed — `NULL` is not a duplicate of `NULL`."""
    async with db_sessionmaker() as db:
        await _shelved(db)

    for title in ("A book with no number", "Another with no number"):
        resp = await client.post("/catalog/works", json={"title": title})
        assert resp.status_code == 201, resp.text


async def test_a_non_isbn_integrity_error_is_not_relabelled(db_sessionmaker):
    """The backstop reads the constraint name before blaming the ISBN — a
    foreign-key failure mislabelled `isbn_exists` would send whoever debugs it
    next straight past the real cause."""
    from sqlalchemy.exc import IntegrityError

    fk = IntegrityError(
        "stmt", {}, Exception('violates foreign key constraint "editions_work_id_fkey"')
    )
    assert not catalog_service._is_isbn_violation(fk)

    dup = IntegrityError(
        "stmt", {}, Exception('duplicate key value violates unique constraint "editions_isbn_key"')
    )
    assert catalog_service._is_isbn_violation(dup)
