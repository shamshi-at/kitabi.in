"""Backfill edition cover images from OpenLibrary, then Wikipedia.

For every edition with no cover_url, tries in order: the OpenLibrary cover by
ISBN (exact, no mismatch risk), an OpenLibrary title(+author) search, then a
Wikipedia article-image lookup (keyless — better coverage for famous regional /
Malayalam titles). Each fallback is guarded against a wrong match: OpenLibrary by
shared title word, Wikipedia by requiring a book-ish category (and rejecting
film/album pages) so we never paste a film poster on a novel. Idempotent:
re-running only touches editions still missing a cover.

Run from the api/ directory:

    .venv/bin/python scripts/backfill_covers.py            # ISBN + guarded search
    .venv/bin/python scripts/backfill_covers.py --isbn-only

Targets whatever DATABASE_URL resolves to (export the Supavisor pooler URL to
backfill production, same as seed_catalog.py). Every assignment is printed so
the run can be eyeballed.
"""

import asyncio
import sys
from pathlib import Path

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.orm import joinedload

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))  # `app` package

from app.core.config import get_settings  # noqa: E402
from app.core.db import _engine_kwargs, _normalize  # noqa: E402
from app.models import Edition, Work  # noqa: E402

COVERS = "https://covers.openlibrary.org"
SEARCH = "https://openlibrary.org/search.json"
WIKI = "https://en.wikipedia.org/w/api.php"
_STOP = {"the", "a", "an", "of", "and", "de", "la"}
# Wikipedia's lead image is the book cover only when the article is about a book —
# require a book-ish category and reject films/albums/disambiguation so we never
# paste a film poster on a novel.
_BOOKISH = ("novel", "book", "short stor", "story collect", "poetry", "memoir", "play")
_NOT_BOOK = ("film", "album", "song", "disambiguation", "television")


def _words(text: str) -> set[str]:
    return {w for w in "".join(c.lower() if c.isalnum() else " " for c in text).split() if w}


async def _cover_by_isbn(http: httpx.AsyncClient, isbn: str) -> str | None:
    clean = isbn.replace("-", "").strip()
    url = f"{COVERS}/b/isbn/{clean}-L.jpg"
    try:
        # ?default=false → 404 when OpenLibrary has no real cover for this ISBN.
        r = await http.head(f"{url}?default=false", timeout=15, follow_redirects=True)
        return url if r.status_code == 200 else None
    except httpx.HTTPError:
        return None


async def _cover_by_search(http: httpx.AsyncClient, title: str, author: str | None) -> str | None:
    query = title if not author else f"{title} {author}"
    try:
        r = await http.get(
            SEARCH,
            params={"q": query, "limit": 1, "fields": "cover_i,title"},
            timeout=20,
        )
        docs = r.json().get("docs", [])
    except (httpx.HTTPError, ValueError):
        return None
    if not docs or not docs[0].get("cover_i"):
        return None
    # Guard against a confident-but-wrong match: require a shared significant
    # word between our title and OpenLibrary's.
    ours = _words(title) - _STOP
    theirs = _words(docs[0].get("title", "")) - _STOP
    if not ours or ours.isdisjoint(theirs):
        return None
    return f"{COVERS}/b/id/{docs[0]['cover_i']}-L.jpg"


async def _cover_by_wikipedia(
    http: httpx.AsyncClient, title: str, author: str | None
) -> str | None:
    ours = _words(title) - _STOP
    if not ours:
        return None
    try:
        r = await http.get(
            WIKI,
            params={
                "action": "query",
                "list": "search",
                "srsearch": f"{title} {author}" if author else title,
                "srlimit": 3,
                "format": "json",
            },
            timeout=20,
        )
        hits = r.json().get("query", {}).get("search", [])
    except (httpx.HTTPError, ValueError):
        return None
    for hit in hits:
        page = hit.get("title", "")
        # The article title must share a significant word with ours.
        if ours.isdisjoint(_words(page) - _STOP):
            continue
        try:
            r2 = await http.get(
                WIKI,
                params={
                    "action": "query",
                    "titles": page,
                    "prop": "pageimages|categories",
                    "piprop": "thumbnail",
                    "pithumbsize": 600,
                    "cllimit": "max",
                    "clshow": "!hidden",
                    "format": "json",
                },
                timeout=20,
            )
            pages = r2.json().get("query", {}).get("pages", {})
        except (httpx.HTTPError, ValueError):
            continue
        for pg in pages.values():
            cats = " ".join(c.get("title", "").lower() for c in pg.get("categories", []))
            if any(bad in cats for bad in _NOT_BOOK):
                continue
            if not any(good in cats for good in _BOOKISH):
                continue
            thumb = (pg.get("thumbnail") or {}).get("source")
            if thumb:
                return thumb
    return None


async def backfill(isbn_only: bool) -> None:
    settings = get_settings()
    url = _normalize(settings.database_url)
    engine = create_async_engine(url, **_engine_kwargs(url))
    sm = async_sessionmaker(engine, expire_on_commit=False)
    scanned = updated = 0

    async with httpx.AsyncClient(headers={"User-Agent": "kitabi-cover-backfill/1.0"}) as http:
        async with sm() as session:
            stmt = (
                select(Edition)
                .where(Edition.cover_url.is_(None), Edition.deleted_at.is_(None))
                .options(joinedload(Edition.work).selectinload(Work.authors))
            )
            editions = (await session.execute(stmt)).scalars().unique().all()
            for ed in editions:
                scanned += 1
                cover = await _cover_by_isbn(http, ed.isbn) if ed.isbn else None
                if cover is None and not isbn_only and ed.work is not None:
                    author = ed.work.authors[0].name if ed.work.authors else None
                    cover = await _cover_by_search(http, ed.work.title, author)
                    if cover is None:
                        cover = await _cover_by_wikipedia(http, ed.work.title, author)
                if cover:
                    ed.cover_url = cover
                    updated += 1
                    title = ed.work.title if ed.work else str(ed.id)
                    print(f"  ✓ {title} → {cover}")
                await asyncio.sleep(0.2)  # be gentle to OpenLibrary
            await session.commit()
    await engine.dispose()
    print(f"\nBackfill complete: {updated}/{scanned} cover-less editions given a cover.")


if __name__ == "__main__":
    asyncio.run(backfill(isbn_only="--isbn-only" in sys.argv))
