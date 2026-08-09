"""The generated Amazon buy link (services/buy_links.py) and its journey to
both read surfaces — /public/book/{slug} (web) and /catalog/works/{id} (app).

The revenue rule under test (docs/revenue-plan.md §3.1, Amazon-only since
9 Aug 2026): the one served link is computed at read time from the ISBN,
tagged only when the affiliate tag is configured, and `affiliate` is True
only for a link that actually pays — the disclosure both clients render
hangs off that flag, so a wrong True is a false confession and a wrong False
is an undisclosed ad. A stored Amazon link (the admin console's per-edition
field) wins over the generated one; stored non-Amazon links stay in the
JSONB but are not served.
"""

import uuid

from app.core.config import get_settings
from app.models import Author, Edition, Work
from app.services import buy_links, slug_service

TAG = "kitabi0f-21"
ISBN10 = "8126403454"
ISBN13 = "9788126403455"
# Checksum-valid, 979-prefixed: no ISBN-10 exists for it (services/isbn.py).
ISBN13_979 = "9791234567896"


def merged(stored=None, *, isbn=None, title="Chemmeen", author="Thakazhi", tag=""):
    return buy_links.merged(stored, isbn=isbn, title=title, author=author, amazon_tag=tag)


def only(links: list[dict]) -> dict:
    assert len(links) == 1, f"exactly one link is served, got {links}"
    assert links[0]["retailer"] == "Amazon"
    return links[0]


# --------------------------------------------------------------------------
# The URL arithmetic (pure)
# --------------------------------------------------------------------------


def test_isbn13_becomes_a_direct_amazon_product_link():
    """A printed book's ASIN is its ISBN-10, so a stored ISBN-13 still yields
    a /dp/ product page, not a search."""
    amazon = only(merged(isbn=ISBN13, tag=TAG))
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
    assert amazon["affiliate"] is True


def test_isbn10_input_is_also_direct():
    assert (
        only(merged(isbn=ISBN10, tag=TAG))["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
    )


def test_979_isbn_has_no_isbn10_so_amazon_gets_a_search():
    amazon = only(merged(isbn=ISBN13_979, tag=TAG))
    assert "/dp/" not in amazon["url"]
    assert amazon["url"] == f"https://www.amazon.in/s?k={ISBN13_979}&tag={TAG}"
    assert amazon["affiliate"] is True


def test_checksum_invalid_isbn_searches_by_title_not_the_bad_number():
    """A mis-keyed ISBN converted or searched verbatim finds nothing — or a
    different product. The title at least finds the right shelf."""
    amazon = only(merged(isbn="8126403455", tag=TAG))  # bad check digit
    assert "8126403455" not in amazon["url"]
    assert "k=Chemmeen+Thakazhi" in amazon["url"]


def test_no_isbn_searches_title_and_author_url_encoded():
    amazon = only(merged(title="ഖസാക്കിന്റെ ഇതിഹാസം", author="O. V. Vijayan"))
    assert amazon["url"].startswith("https://www.amazon.in/s?k=%E0%B4%96")
    assert "+O.+V.+Vijayan" in amazon["url"]


def test_untagged_link_still_renders_but_confesses_nothing():
    """No affiliate tag configured → the button still serves readers, earns
    nothing, and must not claim otherwise (no disclosure trigger)."""
    amazon = only(merged(isbn=ISBN13))
    assert "tag=" not in amazon["url"]
    assert amazon["affiliate"] is False


# --------------------------------------------------------------------------
# Merging with the stored, admin/contributor-entered link
# --------------------------------------------------------------------------


def test_stored_amazon_link_gets_our_tag_and_suppresses_the_generated_one():
    stored = [{"retailer": "Amazon.in", "url": "https://www.amazon.in/dp/x123"}]
    amazon = only(merged(stored, isbn=ISBN13, tag=TAG))
    assert amazon["url"] == f"https://www.amazon.in/dp/x123?tag={TAG}"
    assert amazon["affiliate"] is True


def test_a_foreign_tag_on_a_stored_link_is_left_alone():
    """Overwriting someone's attribution is not ours to do — and a link that
    pays someone else must not trigger OUR disclosure."""
    stored = [{"retailer": "Amazon.in", "url": "https://www.amazon.in/dp/x?tag=other-21"}]
    amazon = only(merged(stored, tag=TAG))
    assert amazon["url"] == "https://www.amazon.in/dp/x?tag=other-21"
    assert amazon["affiliate"] is False


def test_our_own_tag_already_present_still_counts_as_affiliate():
    stored = [{"retailer": "Amazon.in", "url": f"https://www.amazon.in/dp/x?tag={TAG}"}]
    assert only(merged(stored, tag=TAG))["affiliate"] is True


def test_short_links_and_foreign_marketplaces_win_but_are_never_tagged():
    """amzn.to goes through Amazon's resolver (added params are dropped);
    amazon.com is a different Associates programme (tagging mis-attributes)."""
    for url in ("https://amzn.to/abc", "https://www.amazon.com/dp/x123"):
        amazon = only(merged([{"retailer": "Amazon", "url": url}], isbn=ISBN13, tag=TAG))
        assert amazon["url"] == url
        assert amazon["affiliate"] is False


def test_non_amazon_stored_links_are_kept_in_the_jsonb_but_not_served():
    """The one-button policy: a DC Books or Flipkart link a contributor once
    typed stays stored (merged never mutates the list) yet the page serves
    only Amazon."""
    stored = [
        {"retailer": "DC Books", "url": "https://onlinestore.dcbooks.com/x"},
        {"retailer": "Flipkart", "url": "https://www.flipkart.com/x/p/itm123"},
    ]
    amazon = only(merged(stored, isbn=ISBN13, tag=TAG))
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
    assert stored[0] == {"retailer": "DC Books", "url": "https://onlinestore.dcbooks.com/x"}


def test_the_first_amazon_entry_wins_over_later_ones():
    stored = [
        {"retailer": "DC Books", "url": "https://onlinestore.dcbooks.com/x"},
        {"retailer": "Amazon", "url": "https://www.amazon.in/dp/first"},
        {"retailer": "Amazon", "url": "https://www.amazon.in/dp/second"},
    ]
    assert only(merged(stored, tag=""))["url"] == "https://www.amazon.in/dp/first"


def test_malformed_stored_entries_are_skipped_not_fatal():
    stored = [None, "not-a-dict", {"retailer": "A"}, {"url": ""}, {"url": "http://[::1"}]
    amazon = only(merged(stored, isbn=ISBN13))
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}"


def test_is_amazon_family_detection():
    """The admin console's Amazon-link field validates with this."""
    for url in (
        "https://www.amazon.in/dp/x",
        "https://amazon.in/dp/x",
        "https://amzn.to/abc",
        "https://www.amazon.com/dp/x",
    ):
        assert buy_links.is_amazon(url), url
    for url in ("https://www.flipkart.com/x", "https://myamazon.example/x", "not a url"):
        assert not buy_links.is_amazon(url), url


# --------------------------------------------------------------------------
# The two read surfaces
# --------------------------------------------------------------------------


async def _seed(db, *, isbn=None, stored=None, title="Chemmeen"):
    author = Author(name="Thakazhi Sivasankara Pillai")
    db.add(author)
    await db.flush()
    await slug_service.ensure_slug(db, author)
    work = Work(title=title, authors=[author])
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id, isbn=isbn, buy_links=stored)
    db.add(edition)
    await slug_service.ensure_slug(db, work, extras=[author.name])
    await db.commit()
    return work, edition


async def test_public_book_page_serves_the_generated_affiliate_link(
    db_sessionmaker, unauthenticated_client, monkeypatch
):
    patched = get_settings().model_copy(update={"amazon_associate_tag": TAG})
    monkeypatch.setattr("app.services.public_service.get_settings", lambda: patched)
    async with db_sessionmaker() as db:
        work, _ = await _seed(db, isbn=ISBN13)

    resp = await unauthenticated_client.get(f"/public/book/{work.slug}")
    assert resp.status_code == 200
    amazon = only(resp.json()["editions"][0]["buy_links"])
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
    assert amazon["affiliate"] is True


async def test_catalog_work_response_carries_the_link_for_the_app(
    db_sessionmaker, client, monkeypatch
):
    """The app's book page reads GET /catalog/works/{id} (and the borrowed-book
    path GET /catalog/editions/{id}, same serializer) — the link appears there
    with no app release."""
    patched = get_settings().model_copy(update={"amazon_associate_tag": TAG})
    monkeypatch.setattr("app.api.catalog.get_settings", lambda: patched)
    async with db_sessionmaker() as db:
        work, edition = await _seed(db, isbn=ISBN13)

    for url in (f"/catalog/works/{work.id}", f"/catalog/editions/{edition.id}"):
        resp = await client.get(url)
        assert resp.status_code == 200, url
        amazon = only(resp.json()["editions"][0]["buy_links"])
        assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"


async def test_stored_amazon_link_leads_on_the_public_page(
    db_sessionmaker, unauthenticated_client, monkeypatch
):
    untagged = get_settings().model_copy(update={"amazon_associate_tag": ""})
    monkeypatch.setattr("app.services.public_service.get_settings", lambda: untagged)
    async with db_sessionmaker() as db:
        work, _ = await _seed(
            db,
            isbn=ISBN13,
            stored=[
                {"retailer": "DC Books", "url": "https://dcbooks.example/x"},
                {"retailer": "Amazon", "url": "https://www.amazon.in/dp/exact"},
            ],
        )

    resp = await unauthenticated_client.get(f"/public/book/{work.slug}")
    amazon = only(resp.json()["editions"][0]["buy_links"])
    assert amazon["url"] == "https://www.amazon.in/dp/exact"
    assert amazon["affiliate"] is False, "nothing configured, nothing claimed"


async def test_the_stored_shape_stays_clean_on_write(db_sessionmaker, client):
    """A client that echoes the served shape back (affiliate flag included)
    must not get computed fields into the JSONB — the column stays exactly
    {retailer, url}, so read-time generation remains the single source."""
    async with db_sessionmaker() as db:
        work, edition = await _seed(db, isbn=ISBN13)

    resp = await client.patch(
        f"/catalog/editions/{edition.id}",
        json={
            "buy_links": [
                {"retailer": "DC Books", "url": "https://dcbooks.example/x", "affiliate": True}
            ]
        },
    )
    assert resp.status_code == 200
    async with db_sessionmaker() as db:
        row = await db.get(Edition, uuid.UUID(str(edition.id)))
        assert row.buy_links == [{"retailer": "DC Books", "url": "https://dcbooks.example/x"}]
