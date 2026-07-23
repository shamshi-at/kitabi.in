"""Sitemap generation for the public share pages (kitabi.in/b|/a|/p) — a
sitemap index plus paged urlsets over the live catalog, so search engines can
discover every work/author/publisher without crawling. Served by the API,
proxied to kitabi.in/sitemaps/* by a Pages Function (the crawler-facing host)."""

from math import ceil
from xml.sax.saxutils import escape

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Author, Publisher, Work

# The crawler-facing origin. Hardcoded like the Pages Functions hardcode their
# API base — these URLs must be the public share links, never the API host.
PUBLIC_BASE = "https://kitabi.in"

# Sitemap protocol caps a urlset at 50,000 URLs / 50 MB; 10,000 keeps each
# response small and the page count stable-ish as the catalog grows.
PAGE_SIZE = 10_000

# kind -> (model, share-path prefix). Order fixed so the index is deterministic.
_KINDS: dict[str, tuple[type, str]] = {
    "works": (Work, "/b/"),
    "authors": (Author, "/a/"),
    "publishers": (Publisher, "/p/"),
}

_XML_DECL = '<?xml version="1.0" encoding="UTF-8"?>'
_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"


def _not_found(message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={"code": "not_found", "message": message},
    )


async def build_index(db: AsyncSession) -> str:
    """The <sitemapindex>: one entry per page of each kind. A kind with zero
    live rows contributes no entries; an empty catalog is a valid empty index."""
    entries: list[str] = []
    for kind, (model, _) in _KINDS.items():
        count = await db.scalar(
            select(func.count()).select_from(model).where(model.deleted_at.is_(None))
        )
        for page in range(1, ceil((count or 0) / PAGE_SIZE) + 1):
            loc = escape(f"{PUBLIC_BASE}/sitemaps/{kind}-{page}.xml")
            entries.append(f"<sitemap><loc>{loc}</loc></sitemap>")
    return f'{_XML_DECL}\n<sitemapindex xmlns="{_NS}">{"".join(entries)}</sitemapindex>\n'


async def build_page(db: AsyncSession, kind: str, page: int) -> str:
    """One <urlset> page (up to PAGE_SIZE entries) of a kind, ordered by
    (created_at, id) so pagination stays stable as rows are added. 404s on an
    unknown kind or a page past the end (including page 1 of an empty kind)."""
    if kind not in _KINDS:
        raise _not_found("Unknown sitemap")
    if page < 1:
        raise _not_found("Sitemap page out of range")

    model, prefix = _KINDS[kind]
    rows = (
        await db.execute(
            select(model.id, model.updated_at)
            .where(model.deleted_at.is_(None))
            .order_by(model.created_at, model.id)
            .offset((page - 1) * PAGE_SIZE)
            .limit(PAGE_SIZE)
        )
    ).all()
    if not rows:
        raise _not_found("Sitemap page out of range")

    urls: list[str] = []
    for row_id, updated_at in rows:
        # Ids are UUIDs today, so escaping is future-proofing, not decoration.
        loc = escape(f"{PUBLIC_BASE}{prefix}{row_id}")
        lastmod = updated_at.date().isoformat()
        urls.append(f"<url><loc>{loc}</loc><lastmod>{lastmod}</lastmod></url>")
    return f'{_XML_DECL}\n<urlset xmlns="{_NS}">{"".join(urls)}</urlset>\n'
