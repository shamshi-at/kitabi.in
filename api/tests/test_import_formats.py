"""Reading a Libib or LibraryThing export, and not changing how a Goodreads one
reads.

Every header row in `fixtures/imports/` is copied byte-for-byte from a real
export (the README there says which), and the data rows are written in that
export's own cell format — Libib's leading-space statuses, LibraryThing's
bracketed ISBNs and dates. Written from what the parser happens to read, a
fixture can only agree with the parser (CLAUDE.md, 9 Aug 2026); these were
written from the files, and the parser was then made to read them.
"""

from dataclasses import asdict
from pathlib import Path

import pytest

from app.services import import_service

FIXTURES = Path(__file__).parent / "fixtures" / "imports"


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def _by_title(rows):
    return {r.title: r for r in rows}


# --- Goodreads: unchanged --------------------------------------------------


def test_a_real_goodreads_export_reads_exactly_as_it_did():
    """The parser's output on a real-header Goodreads export, captured BEFORE
    the Libib/LibraryThing change and pinned here. `date_started` is the one
    new field, and Goodreads has no column for it."""
    text = _fixture("goodreads_export.csv")
    assert import_service.detect_format(text) == "goodreads"
    assert [asdict(r) for r in import_service.parse_csv(text)] == [
        {
            "title": "Chemmeen",
            "author": "Thakazhi Sivasankara Pillai",
            "isbn": "9788126403455",
            "rating": 5,
            "review": "The sea takes what it is owed.",
            "status": "read",
            "date_read": "2024/03/10",
            "tags": ["malayalam", "classics"],
            "date_started": None,
        },
        {
            "title": "Aadujeevitham",
            "author": "Benyamin",
            "isbn": "9788126429981",
            "rating": None,
            "review": None,
            "status": "reading",
            "date_read": None,
            "tags": ["currently-reading"],
            "date_started": None,
        },
        {
            "title": "Khasakkinte Itihasam",
            "author": "O. V. Vijayan",
            "isbn": "9788126415410",  # ISBN-10 column only, canonicalised
            "rating": None,
            "review": None,
            "status": "wishlist",
            "date_read": None,
            "tags": ["to-read"],
            "date_started": None,
        },
    ]


# --- Libib -------------------------------------------------------------------


def test_libib_export_is_detected():
    assert import_service.detect_format(_fixture("libib_export.csv")) == "libib"
    assert import_service.detect_format(_fixture("libib_export_2025.csv")) == "libib"


def test_libib_export_reads_author_isbn_status_dates_and_review():
    rows = _by_title(import_service.parse_csv(_fixture("libib_export.csv")))

    chemmeen = rows["Chemmeen"]
    assert chemmeen.author == "Thakazhi Sivasankara Pillai"  # `creators`
    assert chemmeen.isbn == "9788126403455"  # `ean_isbn13`
    assert chemmeen.status == "read"  # " Completed"
    assert chemmeen.date_started == "2024-02-20"  # `began`
    assert chemmeen.date_read == "2024-03-10"  # `completed`
    assert chemmeen.rating == 5  # 4.5 — a half star rounds up
    assert chemmeen.review == "The sea takes what it is owed."
    assert chemmeen.tags == ["malayalam", "classics"]

    aadu = rows["Aadujeevitham"]
    assert aadu.status == "reading"  # " In progress"
    assert aadu.date_started == "2026-10-01"
    assert aadu.date_read is None  # `completed` is " " until it isn't

    # `ean_isbn13` empty: the `upc_isbn10` column is read and lands on the
    # same ISBN-13 the catalogue stores.
    khasak = rows["Khasakkinte Itihasam"]
    assert khasak.isbn == "9788126415410"
    assert khasak.author == "O. V. Vijayan"
    assert khasak.status == "pending"  # " Not begun" — on the shelf, unread

    assert rows["Randamoozham"].status == "stopped"  # " Abandoned"
    assert rows["Randamoozham"].rating == 3

    # Several creators stay one credit line; no status at all stays None
    # (the app files it as `pending`, same as "Not begun").
    stories = rows["Malayalam Short Stories"]
    assert stories.author == "Lalithambika Antharjanam, K. Saraswathi Amma"
    assert stories.status is None


def test_libib_private_notes_are_never_a_review():
    """`notes` is the reader's note on their copy. The generic aliases would
    take it as the review whenever `review` is empty (rule 13)."""
    rows = _by_title(import_service.parse_csv(_fixture("libib_export.csv")))
    assert rows["Khasakkinte Itihasam"].review is None
    assert rows["Chemmeen"].review == "The sea takes what it is owed."


def test_libib_non_book_items_are_skipped():
    """A Libib collection holds films and music beside books. The 1965 film
    of Chemmeen must not reach the title matcher as the novel."""
    rows = import_service.parse_csv(_fixture("libib_export.csv"))
    assert [r.title for r in rows] == [
        "Chemmeen",
        "Aadujeevitham",
        "Khasakkinte Itihasam",
        "Randamoozham",
        "Malayalam Short Stories",
    ]


def test_libib_export_from_before_the_id_column():
    """Exports before late 2026 have no leading `id` column."""
    [row] = import_service.parse_csv(_fixture("libib_export_2025.csv"))
    assert row.author == "Thakazhi Sivasankara Pillai"
    assert row.isbn == "9788126403455"
    assert row.status == "read"
    assert row.date_read == "2024-03-10"
    assert row.date_started is None  # `began` is " "


# --- LibraryThing --------------------------------------------------------------


@pytest.mark.parametrize("name", ["librarything_export.csv", "librarything_export.tsv"])
def test_librarything_export_reads_author_isbn_status_dates_and_review(name):
    """LibraryThing offers the same columns comma-separated and tab-delimited;
    the tab file also brackets its dates. Both read the same."""
    text = _fixture(name)
    assert import_service.detect_format(text) == "librarything"
    rows = import_service.parse_csv(text)
    assert [r.title for r in rows] == [
        "Chemmeen",
        "Aadujeevitham",
        "Khasakkinte Itihasam",
        "Oru Desathinte Katha",
    ]
    chemmeen, aadu, khasak, desam = rows

    # `Primary Author` is surname-first; Kitabi credits read forenames first.
    assert chemmeen.author == "Thakazhi Sivasankara Pillai"
    assert khasak.author == "O. V. Vijayan"
    assert aadu.author == "Benyamin"  # a single name is left alone

    assert chemmeen.isbn == "9788126403455"  # `[8126403454]`
    assert aadu.isbn == "9788126429981"
    assert khasak.isbn == "9788126415410"  # `[812641541X]`
    assert desam.isbn is None  # empty, or `[]` in the tab file

    # No status column: a finish date is a read book, a start date alone one
    # being read, neither leaves it to the app's default.
    assert (chemmeen.status, chemmeen.date_started, chemmeen.date_read) == (
        "read",
        "2024-02-20",
        "2024-03-10",
    )
    assert (aadu.status, aadu.date_started, aadu.date_read) == ("reading", "2026-10-01", None)
    assert khasak.status is None and desam.status is None

    assert chemmeen.rating == 5  # 4.5
    assert desam.rating == 3
    assert chemmeen.tags == ["malayalam", "classics"]

    # `Review` is the review; `Comment` and `Private Comment` are notes.
    assert chemmeen.review == "The sea takes what it is owed."
    assert khasak.review is None


# --- shared rules ------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "stars"),
    [("5", 5), ("4", 4), ("4.5", 5), ("4.4", 4), ("0.5", 1), ("0", None), ("", None)],
)
def test_half_star_ratings_round_up_and_zero_is_unrated(raw, stars):
    rows = import_service.parse_csv(f"Title,Rating\nChemmeen,{raw}\n")
    assert rows[0].rating == stars


@pytest.mark.parametrize(
    ("written", "credited"),
    [
        ("Vijayan, O. V.", "O. V. Vijayan"),
        ("Benyamin", "Benyamin"),
        ("Nair, M. T. Vasudevan, Jr.", "Nair, M. T. Vasudevan, Jr."),  # not guessed at
    ],
)
def test_librarything_surname_first_is_only_turned_round_when_plain(written, credited):
    text = f'Title,Primary Author\nChemmeen,"{written}"\n'
    assert import_service.parse_csv(text)[0].author == credited


def test_a_byte_order_mark_does_not_hide_the_first_column():
    """Excel writes one when it saves a CSV; glued to `Title`, it hid every
    title and the whole file imported as nothing."""
    rows = import_service.parse_csv("﻿Title,Author\nChemmeen,Thakazhi\n")
    assert [r.title for r in rows] == ["Chemmeen"]


# --- the endpoint ------------------------------------------------------------


async def _seed(client, title: str, isbn: str) -> None:
    resp = await client.post("/catalog/works", json={"title": title, "isbn": isbn})
    assert resp.status_code in (200, 201), resp.text


@pytest.mark.parametrize(
    ("name", "fmt"),
    [
        ("libib_export.csv", "libib"),
        ("librarything_export.csv", "librarything"),
        ("librarything_export.tsv", "librarything"),
    ],
)
async def test_import_preview_matches_libib_and_librarything_by_isbn(client, name, fmt):
    """Seeded under titles no import row contains, so the title fallback can
    find nothing and only the ISBN can make these matches — Khasakkinte
    Itihasam's through the 10-digit column alone."""
    await _seed(client, "Probe One", "9788126403455")
    await _seed(client, "Probe Two", "9788126415410")

    resp = await client.post("/import/preview", json={"csv": _fixture(name)})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["format"] == fmt
    assert body["matched"] == 2
    rows = {r["title"]: r for r in body["rows"]}
    assert rows["Chemmeen"]["match"]["title"] == "Probe One"
    assert rows["Khasakkinte Itihasam"]["match"]["title"] == "Probe Two"
    assert rows["Chemmeen"]["author"] == "Thakazhi Sivasankara Pillai"
    assert rows["Chemmeen"]["status"] == "read"
    assert rows["Chemmeen"]["date_started"] == "2024-02-20"
