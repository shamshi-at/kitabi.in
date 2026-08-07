"""Generated retailer links (services/buy_links.py) and their journey to both
read surfaces — /public/book/{slug} (web) and /catalog/works/{id} (app).

The revenue rule under test (docs/revenue-plan.md §3.1): links are computed at
read time from the ISBN, tagged only when an affiliate id is configured, and
`affiliate` is True only for a link that actually pays — the disclosure both
clients render hangs off that flag, so a wrong True is a false confession and
a wrong False is an undisclosed ad.
"""

import uuid

from app.core.config import get_settings
from app.models import Author, Edition, Work
from app.services import buy_links, slug_service

TAG = "kitabi0f-21"
AFFID = "kitabi"
ISBN10 = "8126403454"
ISBN13 = "9788126403455"
# Checksum-valid, 979-prefixed: no ISBN-10 exists for it (services/isbn.py).
ISBN13_979 = "9791234567896"


def merged(stored=None, *, isbn=None, title="Chemmeen", author="Thakazhi", tag="", affid=""):
    return buy_links.merged(
        stored, isbn=isbn, title=title, author=author, amazon_tag=tag, flipkart_affid=affid
    )


def by_retailer(links: list[dict], retailer: str) -> dict:
    return next(link for link in links if link["retailer"] == retailer)


# --------------------------------------------------------------------------
# The URL arithmetic (pure)
# --------------------------------------------------------------------------


def test_isbn13_becomes_a_direct_amazon_product_link():
    """A printed book's ASIN is its ISBN-10, so a stored ISBN-13 still yields
    a /dp/ product page, not a search."""
    amazon = by_retailer(merged(isbn=ISBN13, tag=TAG), "Amazon")
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
    assert amazon["affiliate"] is True


def test_isbn10_input_is_also_direct():
    amazon = by_retailer(merged(isbn=ISBN10, tag=TAG), "Amazon")
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"


def test_979_isbn_has_no_isbn10_so_amazon_gets_a_search():
    amazon = by_retailer(merged(isbn=ISBN13_979, tag=TAG), "Amazon")
    assert "/dp/" not in amazon["url"]
    assert amazon["url"] == f"https://www.amazon.in/s?k={ISBN13_979}&tag={TAG}"
    assert amazon["affiliate"] is True


def test_checksum_invalid_isbn_searches_by_title_not_the_bad_number():
    """A mis-keyed ISBN converted or searched verbatim finds nothing — or a
    different product. The title at least finds the right shelf."""
    links = merged(isbn="8126403455", tag=TAG)  # bad check digit
    for link in links:
        assert "8126403455" not in link["url"]
    assert "k=Chemmeen+Thakazhi" in by_retailer(links, "Amazon")["url"]


def test_no_isbn_searches_title_and_author_url_encoded():
    links = merged(title="ഖസാക്കിന്റെ ഇതിഹാസം", author="O. V. Vijayan")
    amazon = by_retailer(links, "Amazon")
    assert amazon["url"].startswith("https://www.amazon.in/s?k=%E0%B4%96")
    assert "+O.+V.+Vijayan" in amazon["url"]
    flipkart = by_retailer(links, "Flipkart")
    assert flipkart["url"].startswith("https://www.flipkart.com/search?q=%E0%B4%96")


def test_untagged_links_still_render_but_confess_nothing():
    """No affiliate id configured → the block still serves readers, earns
    nothing, and must not claim otherwise (no disclosure trigger)."""
    links = merged(isbn=ISBN13)
    assert len(links) == 2
    for link in links:
        assert "tag=" not in link["url"]
        assert "affid=" not in link["url"]
        assert link["affiliate"] is False


def test_flipkart_gets_the_affid():
    flipkart = by_retailer(merged(isbn=ISBN13, affid=AFFID), "Flipkart")
    assert flipkart["url"] == f"https://www.flipkart.com/search?q={ISBN13}&affid={AFFID}"
    assert flipkart["affiliate"] is True


# --------------------------------------------------------------------------
# Merging with stored, contributor-entered links
# --------------------------------------------------------------------------


def test_stored_amazon_link_gets_our_tag_and_suppresses_the_generated_one():
    stored = [{"retailer": "Amazon.in", "url": "https://www.amazon.in/dp/x123"}]
    links = merged(stored, isbn=ISBN13, tag=TAG)
    amazons = [link for link in links if "amazon" in link["url"]]
    assert len(amazons) == 1, "one Amazon row, not a stored one plus a generated one"
    assert amazons[0]["url"] == f"https://www.amazon.in/dp/x123?tag={TAG}"
    assert amazons[0]["affiliate"] is True
    assert by_retailer(links, "Flipkart")["url"], "the other family is still generated"


def test_a_foreign_tag_on_a_stored_link_is_left_alone():
    """Overwriting someone's attribution is not ours to do — and a link that
    pays someone else must not trigger OUR disclosure."""
    stored = [{"retailer": "Amazon.in", "url": "https://www.amazon.in/dp/x?tag=other-21"}]
    (amazon,) = [link for link in merged(stored, tag=TAG) if "amazon" in link["url"]]
    assert amazon["url"] == "https://www.amazon.in/dp/x?tag=other-21"
    assert amazon["affiliate"] is False


def test_our_own_tag_already_present_still_counts_as_affiliate():
    stored = [{"retailer": "Amazon.in", "url": f"https://www.amazon.in/dp/x?tag={TAG}"}]
    (amazon,) = [link for link in merged(stored, tag=TAG) if "amazon" in link["url"]]
    assert amazon["affiliate"] is True


def test_short_links_and_foreign_marketplaces_suppress_but_are_never_tagged():
    """amzn.to goes through Amazon's resolver (added params are dropped);
    amazon.com is a different Associates programme (tagging mis-attributes)."""
    for url in ("https://amzn.to/abc", "https://www.amazon.com/dp/x123"):
        links = merged([{"retailer": "Amazon", "url": url}], isbn=ISBN13, tag=TAG)
        family = [link for link in links if link["retailer"] != "Flipkart"]
        assert [link["url"] for link in family] == [url], url
        assert family[0]["affiliate"] is False


def test_a_publisher_store_link_leads_and_both_retailers_still_generate():
    stored = [{"retailer": "DC Books", "url": "https://onlinestore.dcbooks.com/x"}]
    links = merged(stored, isbn=ISBN13)
    assert [link["retailer"] for link in links] == ["DC Books", "Amazon", "Flipkart"]
    assert links[0]["url"] == "https://onlinestore.dcbooks.com/x"


def test_malformed_stored_entries_are_skipped_not_fatal():
    stored = [None, "not-a-dict", {"retailer": "A"}, {"url": ""}, {"url": "http://[::1"}]
    links = merged(stored, isbn=ISBN13)
    # The unparseable-host URL survives verbatim (family unknown, kept as-is);
    # the shapeless entries are dropped; both retailers still generate.
    assert [link["retailer"] for link in links] == ["", "Amazon", "Flipkart"]
    assert links[0]["url"] == "http://[::1"


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


async def test_public_book_page_serves_generated_affiliate_links(
    db_sessionmaker, unauthenticated_client, monkeypatch
):
    patched = get_settings().model_copy(update={"amazon_associate_tag": TAG})
    monkeypatch.setattr("app.services.public_service.get_settings", lambda: patched)
    async with db_sessionmaker() as db:
        work, _ = await _seed(db, isbn=ISBN13)

    resp = await unauthenticated_client.get(f"/public/book/{work.slug}")
    assert resp.status_code == 200
    links = resp.json()["editions"][0]["buy_links"]
    amazon = by_retailer(links, "Amazon")
    assert amazon["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
    assert amazon["affiliate"] is True
    assert by_retailer(links, "Flipkart")["affiliate"] is False  # no affid configured


async def test_catalog_work_response_carries_links_for_the_app(
    db_sessionmaker, client, monkeypatch
):
    """The app's book page reads GET /catalog/works/{id} (and the borrowed-book
    path GET /catalog/editions/{id}, same serializer) — links appear there with
    no app release."""
    patched = get_settings().model_copy(
        update={"amazon_associate_tag": TAG, "flipkart_affiliate_id": AFFID}
    )
    monkeypatch.setattr("app.api.catalog.get_settings", lambda: patched)
    async with db_sessionmaker() as db:
        work, edition = await _seed(db, isbn=ISBN13)

    for url in (f"/catalog/works/{work.id}", f"/catalog/editions/{edition.id}"):
        resp = await client.get(url)
        assert resp.status_code == 200, url
        links = resp.json()["editions"][0]["buy_links"]
        assert by_retailer(links, "Amazon")["url"] == f"https://www.amazon.in/dp/{ISBN10}?tag={TAG}"
        flipkart = by_retailer(links, "Flipkart")
        assert f"affid={AFFID}" in flipkart["url"] and flipkart["affiliate"] is True


async def test_stored_links_lead_and_untagged_generation_still_happens(
    db_sessionmaker, unauthenticated_client, monkeypatch
):
    untagged = get_settings().model_copy(
        update={"amazon_associate_tag": "", "flipkart_affiliate_id": ""}
    )
    monkeypatch.setattr("app.services.public_service.get_settings", lambda: untagged)
    async with db_sessionmaker() as db:
        work, _ = await _seed(
            db, isbn=ISBN13, stored=[{"retailer": "DC Books", "url": "https://dcbooks.example/x"}]
        )

    resp = await unauthenticated_client.get(f"/public/book/{work.slug}")
    links = resp.json()["editions"][0]["buy_links"]
    assert [link["retailer"] for link in links] == ["DC Books", "Amazon", "Flipkart"]
    assert all(link["affiliate"] is False for link in links), "nothing configured, nothing claimed"


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
