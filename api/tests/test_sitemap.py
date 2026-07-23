"""Sitemap endpoints: the index lists one page file per kind with live rows,
pages emit /b|/a|/p share URLs with a lastmod, unknown kinds and out-of-range
pages 404 with the structured detail shape, and an empty catalog still yields
a valid (empty) index. All public — fetched through unauthenticated_client."""

import uuid
import xml.etree.ElementTree as ET
from datetime import UTC, datetime

from app.models import Author, Publisher, Work

NS = "{http://www.sitemaps.org/schemas/sitemap/0.9}"


async def _seed(db_sessionmaker) -> tuple[uuid.UUID, uuid.UUID, uuid.UUID]:
    """One live work, author, and publisher, plus a soft-deleted work that
    must never surface in any sitemap."""
    work_id, author_id, publisher_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    async with db_sessionmaker() as db:
        db.add(Work(id=work_id, title="Chemmeen"))
        db.add(Author(id=author_id, name="Thakazhi Sivasankara Pillai"))
        db.add(Publisher(id=publisher_id, name="DC Books"))
        db.add(Work(id=uuid.uuid4(), title="Gone", deleted_at=datetime.now(UTC)))
        await db.commit()
    return work_id, author_id, publisher_id


async def test_index_lists_one_page_per_kind(unauthenticated_client, db_sessionmaker):
    await _seed(db_sessionmaker)
    res = await unauthenticated_client.get("/catalog/sitemap/index.xml")
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("application/xml")
    assert res.headers["cache-control"] == "public, max-age=3600"

    root = ET.fromstring(res.text)
    assert root.tag == f"{NS}sitemapindex"
    locs = [el.text for el in root.iter(f"{NS}loc")]
    assert locs == [
        "https://kitabi.in/sitemaps/works-1.xml",
        "https://kitabi.in/sitemaps/authors-1.xml",
        "https://kitabi.in/sitemaps/publishers-1.xml",
    ]


async def test_works_page_lists_share_url_with_lastmod(unauthenticated_client, db_sessionmaker):
    work_id, _, _ = await _seed(db_sessionmaker)
    res = await unauthenticated_client.get("/catalog/sitemap/works-1.xml")
    assert res.status_code == 200
    assert res.headers["cache-control"] == "public, max-age=3600"

    root = ET.fromstring(res.text)
    assert root.tag == f"{NS}urlset"
    urls = {
        url.find(f"{NS}loc").text: url.find(f"{NS}lastmod").text for url in root.iter(f"{NS}url")
    }
    assert set(urls) == {f"https://kitabi.in/b/{work_id}"}  # soft-deleted row excluded
    assert urls[f"https://kitabi.in/b/{work_id}"] == datetime.now(UTC).date().isoformat()


async def test_author_and_publisher_pages(unauthenticated_client, db_sessionmaker):
    _, author_id, publisher_id = await _seed(db_sessionmaker)
    authors = await unauthenticated_client.get("/catalog/sitemap/authors-1.xml")
    publishers = await unauthenticated_client.get("/catalog/sitemap/publishers-1.xml")
    assert f"<loc>https://kitabi.in/a/{author_id}</loc>" in authors.text
    assert f"<loc>https://kitabi.in/p/{publisher_id}</loc>" in publishers.text


async def test_unknown_kind_404s(unauthenticated_client, db_sessionmaker):
    await _seed(db_sessionmaker)
    res = await unauthenticated_client.get("/catalog/sitemap/gadgets-1.xml")
    assert res.status_code == 404
    assert res.json()["code"] == "not_found"


async def test_out_of_range_page_404s(unauthenticated_client, db_sessionmaker):
    await _seed(db_sessionmaker)
    res = await unauthenticated_client.get("/catalog/sitemap/works-2.xml")
    assert res.status_code == 404
    assert res.json()["code"] == "not_found"


async def test_page_of_empty_kind_404s(unauthenticated_client, db_sessionmaker):
    del db_sessionmaker  # fixture truncates — the catalog is empty
    res = await unauthenticated_client.get("/catalog/sitemap/works-1.xml")
    assert res.status_code == 404
    assert res.json()["code"] == "not_found"


async def test_empty_catalog_yields_valid_empty_index(unauthenticated_client, db_sessionmaker):
    del db_sessionmaker  # fixture truncates — the catalog is empty
    res = await unauthenticated_client.get("/catalog/sitemap/index.xml")
    assert res.status_code == 200
    root = ET.fromstring(res.text)
    assert root.tag == f"{NS}sitemapindex"
    assert list(root) == []
