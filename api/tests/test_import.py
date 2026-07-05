from app.services import import_service

_GOODREADS = (
    "Book Id,Title,Author,ISBN,ISBN13,My Rating,My Review,Exclusive Shelf,"
    "Date Read,Bookshelves\n"
    '1,Chemmeen,Thakazhi Sivasankara Pillai,="",="9788126415419",5,'
    'A classic.,read,2024/03/10,"malayalam, classics"\n'
    '2,Aadujeevitham,Benyamin,="",="9788126429981",0,,currently-reading,,\n'
    '3,Some Wishlist Book,Someone,="",="",4,,to-read,,\n'
)

_GENERIC = "Name,By,Rating\nKhasakkinte Itihasam,O.V. Vijayan,5\nNo Rating Book,Author,\n"


def test_parse_goodreads_maps_shelf_rating_isbn_and_tags():
    rows = import_service.parse_csv(_GOODREADS)
    assert [r.title for r in rows] == ["Chemmeen", "Aadujeevitham", "Some Wishlist Book"]

    chemmeen = rows[0]
    assert chemmeen.author == "Thakazhi Sivasankara Pillai"
    assert chemmeen.isbn == "9788126415419"  # unwrapped from ="..."
    assert chemmeen.rating == 5
    assert chemmeen.status == "read"
    assert chemmeen.review == "A classic."
    assert chemmeen.tags == ["malayalam", "classics"]

    assert rows[1].status == "reading"  # currently-reading
    assert rows[1].rating is None  # 0 -> unrated
    assert rows[2].status == "wishlist"  # to-read


def test_is_goodreads_detection():
    assert import_service.is_goodreads(["Title", "My Rating", "Exclusive Shelf"])
    assert not import_service.is_goodreads(["Name", "By", "Rating"])


def test_parse_generic_fuzzy_columns():
    rows = import_service.parse_csv(_GENERIC)
    assert rows[0].title == "Khasakkinte Itihasam"
    assert rows[0].author == "O.V. Vijayan"
    assert rows[0].rating == 5
    assert rows[1].rating is None


def test_parse_skips_rows_without_a_title():
    rows = import_service.parse_csv("Title,Author\n,No Title Here\nReal Book,Someone\n")
    assert [r.title for r in rows] == ["Real Book"]


async def test_import_preview_matches_seeded_catalog(client):
    # Seed a catalog work, then import a CSV that references it by title.
    await client.post("/catalog/works", json={"title": "Naalukettu", "author_names": ["MT"]})
    csv_text = "Title,Author,My Rating,Exclusive Shelf\nNaalukettu,MT,5,read\n"

    resp = await client.post("/import/preview", json={"csv": csv_text})
    assert resp.status_code == 200
    body = resp.json()
    assert body["format"] == "goodreads"  # has My Rating + Exclusive Shelf
    assert body["total"] == 1
    assert body["matched"] == 1
    row = body["rows"][0]
    assert row["status"] == "read"
    assert row["rating"] == 5
    assert row["match"]["title"] == "Naalukettu"


async def test_import_preview_unmatched_row_has_null_match(client):
    csv_text = "Title,Author\nA Book Not In The Catalog XYZ,Nobody\n"
    resp = await client.post("/import/preview", json={"csv": csv_text})
    body = resp.json()
    assert body["matched"] == 0
    assert body["rows"][0]["match"] is None
