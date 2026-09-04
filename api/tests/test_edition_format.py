"""A printing's format — paperback, hardcover — folded onto the four chips.

Asked for as "when it scans and extracts the data, try to find the Format too"
(owner request, 4 Sep 2026). The reliable source turned out not to be the cover
at all: a cover rarely says whether the book is a paperback, while OpenLibrary's
edition record usually does, in `physical_format` — which the ISBN lookup was
reading past. Free text upstream, so it needs folding before it is worth having.
"""

import pytest

from app.schemas.catalog import normalize_edition_format


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("Paperback", "Paperback"),
        ("paperback", "Paperback"),
        ("  Trade  Paperback ", "Paperback"),
        ("Mass Market Paperback", "Paperback"),
        ("pbk.", "Paperback"),
        ("Hardcover", "Hardcover"),
        ("hardback", "Hardcover"),
        ("Electronic resource", "eBook"),
        ("Kindle Edition", "eBook"),
        ("Audio CD", "Audiobook"),
        (None, None),
        ("   ", None),
        # Suggested, not closed — the same bargain WORK_FORMS strikes. A shape
        # we did not think of survives rather than being thrown away.
        ("Leather bound", "Leather bound"),
    ],
)
def test_formats_fold_onto_the_vocabulary(raw, expected):
    assert normalize_edition_format(raw) == expected


async def test_a_scan_records_the_printings_format(client, fake_ol_client):
    """The whole point: the reader scans, and Format is already filled in."""
    fake_ol_client.isbn_responses["9788126429578"] = {
        "title": "Aadujeevitham",
        "authors": [{"name": "Benyamin"}],
        "publishers": [{"name": "DC Books"}],
        "number_of_pages": 212,
        "physical_format": "pbk.",
    }

    resp = await client.get("/catalog/isbn/9788126429578")

    assert resp.status_code == 200, resp.text
    edition = resp.json()["editions"][0]
    assert edition["format"] == "Paperback"
    assert edition["page_count"] == 212


async def test_a_lookup_without_a_format_still_works(client, fake_ol_client):
    fake_ol_client.isbn_responses["9788126429561"] = {
        "title": "Manjaveyil Maranangal",
        "authors": [{"name": "Benyamin"}],
    }

    resp = await client.get("/catalog/isbn/9788126429561")

    assert resp.status_code == 200, resp.text
    assert resp.json()["editions"][0]["format"] is None


async def test_a_typed_format_is_folded_on_the_add_form_too(client):
    """The folding is on the type, not on one endpoint — a reader who types
    "hardback" gets the chip that is actually in the row."""
    resp = await client.post(
        "/catalog/works",
        json={"title": "Randamoozham", "format": "hardback", "isbn": "9788171309876"},
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["editions"][0]["format"] == "Hardcover"
