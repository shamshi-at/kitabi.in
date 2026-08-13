"""Adding a printing to a Work that's already in the catalogue.

Two things the reader in front of the book can supply that the entry usually
can't: which printing is actually theirs, and everything an ISBN-lookup stub
never filled in.
"""

from app.models import Work
from app.services import catalog_service


async def _bare_work(db, title="Naalukett"):
    """The shape a scan leaves behind: a title, and almost nothing else."""
    work = Work(title=title)
    db.add(work)
    await db.flush()
    await db.commit()
    return work


async def test_new_edition_fills_the_works_empty_blurb(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        work = await _bare_work(db)
        work_id = str(work.id)

    resp = await client.post(
        f"/catalog/works/{work_id}/editions",
        json={
            "isbn": "9788126403455",
            "page_count": 240,
            "description": "  A house, four wings, and a boy who leaves it.  ",
            "form": "novel",
            "language": "Malayalam",
            "first_publish_year": 1958,
        },
    )
    assert resp.status_code == 201

    work_resp = await client.get(f"/catalog/works/{work_id}")
    body = work_resp.json()
    assert body["description"] == "A house, four wings, and a boy who leaves it."
    # Folded onto the canonical spelling on the way in, same as the add form.
    assert body["form"] == "Novel"
    assert body["language"] == "Malayalam"
    assert body["first_publish_year"] == 1958


async def test_a_new_edition_never_overwrites_what_the_work_already_says(client, db_sessionmaker):
    """Gap-filling only. The shared catalogue's existing answer wins — this is
    an add-a-printing form, not a back door into editing the book."""
    async with db_sessionmaker() as db:
        work = Work(
            title="Randamoozham",
            description="The Mahabharata told by Bhima.",
            form="Novel",
            language="Malayalam",
            first_publish_year=1984,
        )
        db.add(work)
        await db.flush()
        await db.commit()
        work_id = str(work.id)

    resp = await client.post(
        f"/catalog/works/{work_id}/editions",
        json={
            "description": "Something a reprint's back cover made up.",
            "form": "Play",
            "language": "English",
            "first_publish_year": 2011,
        },
    )
    assert resp.status_code == 201

    body = (await client.get(f"/catalog/works/{work_id}")).json()
    assert body["description"] == "The Mahabharata told by Bhima."
    assert body["form"] == "Novel"
    assert body["language"] == "Malayalam"
    assert body["first_publish_year"] == 1984
    # The edition keeps its own language — a Malayalam book really can have an
    # English printing, and that is edition data, not a correction to the Work.
    assert resp.json()["language"] == "English"


async def test_a_blank_description_is_not_an_answer(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        work = Work(title="Khasakkinte Ithihasam", description="   ")
        db.add(work)
        await db.flush()
        await db.commit()
        work_id = str(work.id)

    await client.post(
        f"/catalog/works/{work_id}/editions",
        json={"description": "Ravi arrives in Khasak."},
    )
    body = (await client.get(f"/catalog/works/{work_id}")).json()
    assert body["description"] == "Ravi arrives in Khasak."


async def test_isbn_lookup_names_the_printing_that_was_scanned(client, db_sessionmaker):
    """The response is the whole Work; the caller has to be told which of its
    editions carries the barcode, or it shelves the wrong page count."""
    created = await client.post(
        "/catalog/works",
        json={"title": "Naalukett", "isbn": "9788126403455", "page_count": 55},
    )
    work_id = created.json()["id"]
    first_edition_id = created.json()["editions"][0]["id"]

    reprint = await client.post(
        f"/catalog/works/{work_id}/editions",
        json={"isbn": "9788171300631", "page_count": 240},
    )
    reprint_id = reprint.json()["id"]

    scanned = await client.get("/catalog/isbn/9788171300631")
    assert scanned.status_code == 200
    body = scanned.json()
    assert len(body["editions"]) == 2
    assert body["scanned_edition_id"] == reprint_id
    assert body["scanned_edition_id"] != first_edition_id


async def test_screenplay_is_an_offered_type(client):
    resp = await client.post(
        "/catalog/works", json={"title": "Naalukett — Thirakkatha", "form": "screenplay"}
    )
    assert resp.status_code == 201
    assert resp.json()["form"] == "Screenplay"
    assert "Screenplay" in catalog_service.WORK_FORMS
