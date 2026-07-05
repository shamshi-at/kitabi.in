"""CSV import parsing (Phase 5 — the front door). Turns a Goodreads export, or
a generic book CSV, into normalized rows the app can match to the catalog and
add to a library. Parsing is pure + unit-tested; catalog matching is a separate
step (`match_row`)."""

import csv
import io
import re
from dataclasses import dataclass, field

# Goodreads "Exclusive Shelf" -> Kitabi reading status (the 5-state enum).
_GOODREADS_SHELF_STATUS = {
    "read": "read",
    "currently-reading": "reading",
    "to-read": "wishlist",
}

# Header aliases for the generic CSV path — matched case-insensitively.
_TITLE_KEYS = ("title", "book", "name", "book title")
_AUTHOR_KEYS = ("author", "authors", "writer", "by")
_ISBN_KEYS = ("isbn13", "isbn 13", "isbn", "isbn10")
_RATING_KEYS = ("my rating", "rating", "stars", "score")
_REVIEW_KEYS = ("my review", "review", "notes", "comment")
_STATUS_KEYS = ("exclusive shelf", "shelf", "status", "bookshelf")
_DATE_READ_KEYS = ("date read", "read date", "finished", "date finished")


@dataclass
class ImportRow:
    title: str
    author: str | None = None
    isbn: str | None = None
    rating: int | None = None  # 1-5, or None when unrated
    review: str | None = None
    status: str | None = None  # a Kitabi status, or None
    date_read: str | None = None  # ISO date string, or None
    tags: list[str] = field(default_factory=list)


def _clean_isbn(raw: str | None) -> str | None:
    """Goodreads wraps ISBNs as `="9780..."`; strip that and any hyphens."""
    if not raw:
        return None
    digits = re.sub(r"[^0-9Xx]", "", raw)
    return digits.upper() if len(digits) in (10, 13) else None


def _clean_rating(raw: str | None) -> int | None:
    if not raw:
        return None
    try:
        value = int(float(raw))
    except ValueError:
        return None
    return value if 1 <= value <= 5 else None


def _map_status(raw: str | None) -> str | None:
    if not raw:
        return None
    key = raw.strip().lower()
    if key in _GOODREADS_SHELF_STATUS:
        return _GOODREADS_SHELF_STATUS[key]
    if key in {"read", "reading", "wishlist", "pending", "stopped"}:
        return key
    return None


def _pick(row: dict[str, str], keys: tuple[str, ...]) -> str | None:
    """First non-empty value whose (lowercased) header matches one of `keys`."""
    lowered = {k.strip().lower(): (v or "").strip() for k, v in row.items() if k}
    for key in keys:
        if lowered.get(key):
            return lowered[key]
    return None


def is_goodreads(headers: list[str]) -> bool:
    lowered = {h.strip().lower() for h in headers}
    return "exclusive shelf" in lowered and "my rating" in lowered


def parse_csv(text: str, limit: int = 2000) -> list[ImportRow]:
    """Parse a Goodreads or generic book CSV into normalized rows. Rows without
    a title are skipped. Capped at `limit` rows."""
    reader = csv.DictReader(io.StringIO(text))
    rows: list[ImportRow] = []
    for raw in reader:
        if len(rows) >= limit:
            break
        title = _pick(raw, _TITLE_KEYS)
        if not title:
            continue
        tags_raw = _pick(raw, ("bookshelves", "tags", "shelves"))
        tags = [t.strip() for t in (tags_raw or "").split(",") if t.strip()] if tags_raw else []
        rows.append(
            ImportRow(
                title=title,
                author=_pick(raw, _AUTHOR_KEYS),
                isbn=_clean_isbn(_pick(raw, _ISBN_KEYS)),
                rating=_clean_rating(_pick(raw, _RATING_KEYS)),
                review=_pick(raw, _REVIEW_KEYS),
                status=_map_status(_pick(raw, _STATUS_KEYS)),
                date_read=_pick(raw, _DATE_READ_KEYS),
                tags=tags,
            )
        )
    return rows
