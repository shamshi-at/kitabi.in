"""OpenLibrary metadata client — the V1 metadata source (STATUS.md: chosen for
zero API key/credential, free, decent global + regional ISBN coverage).

A thin, mockable wrapper: every route depends on `get_openlibrary_client`, so
tests override it with a fake instead of hitting the real network.
"""

import re
from datetime import date
from typing import Any

import httpx

OPENLIBRARY_BASE = "https://openlibrary.org"
COVERS_BASE = "https://covers.openlibrary.org"

_YEAR_RE = re.compile(r"(1[5-9]\d{2}|20\d{2})")


class OpenLibraryClient:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(base_url=OPENLIBRARY_BASE, timeout=8.0)

    async def search(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        resp = await self._client.get("/search.json", params={"q": query, "limit": limit})
        resp.raise_for_status()
        return resp.json().get("docs", [])

    async def lookup_isbn(self, isbn: str) -> dict[str, Any] | None:
        resp = await self._client.get(
            "/api/books",
            params={"bibkeys": f"ISBN:{isbn}", "format": "json", "jscmd": "data"},
        )
        resp.raise_for_status()
        data: dict[str, Any] = resp.json()
        return data.get(f"ISBN:{isbn}")

    @staticmethod
    def cover_url(cover_id: int, size: str = "L") -> str:
        return f"{COVERS_BASE}/b/id/{cover_id}-{size}.jpg"

    async def aclose(self) -> None:
        await self._client.aclose()


def get_openlibrary_client() -> OpenLibraryClient:
    return OpenLibraryClient()


def normalize_isbn_lookup(data: dict[str, Any], isbn: str) -> dict[str, Any]:
    """Flatten OpenLibrary's `jscmd=data` shape into the fields
    catalog_service needs to build a Work + Edition. Publish dates from
    OpenLibrary are often just a year ("2023") or free text ("June 2023") —
    we extract the year for `first_publish_year` and fall back to Jan 1 of
    that year for `pub_date` rather than leave it unset; precision beyond the
    year is lost, which is an acceptable trade for V1.
    """
    authors = [a.get("name") for a in data.get("authors", []) if a.get("name")]
    publishers = [p.get("name") for p in data.get("publishers", []) if p.get("name")]
    year_match = _YEAR_RE.search(data.get("publish_date", "") or "")
    year = int(year_match.group(1)) if year_match else None

    cover = data.get("cover") or {}
    identifiers = data.get("identifiers") or {}
    ol_id = (identifiers.get("openlibrary") or [None])[0]

    return {
        "title": data.get("title") or "Untitled",
        "subtitle": data.get("subtitle"),
        "author_names": authors,
        "publisher_name": publishers[0] if publishers else None,
        "first_publish_year": year,
        "pub_date": date(year, 1, 1) if year else None,
        "page_count": data.get("number_of_pages"),
        "cover_url": cover.get("large") or cover.get("medium") or cover.get("small"),
        "isbn": isbn,
        "external_source": "openlibrary",
        "external_id": ol_id,
    }
