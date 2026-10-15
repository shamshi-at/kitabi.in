"""CSV import parsing (Phase 5 — the front door). Turns a Goodreads, Libib or
LibraryThing export, or a generic book CSV, into normalized rows the app can
match to the catalog and add to a library. Parsing is pure + unit-tested;
catalog matching is a separate step (`match_row`).

A known export is read by its own column names, never through the generic
aliases: Libib's `creators`/`ean_isbn13` and LibraryThing's `Primary Author`
match none of them, and the aliases that *do* match (`notes`, `comment`) would
pour a reader's private notes into a review. The headers each export carries
are pinned by `tests/fixtures/imports/`, copied from real exports — see the
README there.
"""

import csv
import io
import re
from dataclasses import dataclass, field

from app.services import isbn as isbn_util

FORMAT_GOODREADS = "goodreads"
FORMAT_LIBIB = "libib"
FORMAT_LIBRARYTHING = "librarything"
FORMAT_GENERIC = "generic"

# Goodreads "Exclusive Shelf" -> Kitabi reading status (the 5-state enum).
_GOODREADS_SHELF_STATUS = {
    "read": "read",
    "currently-reading": "reading",
    "to-read": "wishlist",
}

# Libib's `status` (its export writes them with a leading space: " Not begun").
# "Not begun" is `pending`, not `wishlist`: Libib catalogues copies a reader
# HAS, so an unstarted book there is one on their shelf — Kitabi's "To read".
# `wishlist` means "don't own it", which on Kitabi invites asking a connection
# to lend it. It also keeps "Not begun" the same as Libib's commonest status,
# none at all, which the app imports as `pending`.
_LIBIB_STATUS = {
    "not begun": "pending",
    "in progress": "reading",
    "completed": "read",
    "abandoned": "stopped",
}

# Header aliases for the generic CSV path — matched case-insensitively.
_TITLE_KEYS = ("title", "book", "name", "book title")
_AUTHOR_KEYS = ("author", "authors", "writer", "by")
_ISBN_KEYS = ("isbn13", "isbn 13", "isbn", "isbn10")
_RATING_KEYS = ("my rating", "rating", "stars", "score")
_REVIEW_KEYS = ("my review", "review", "notes", "comment")
_STATUS_KEYS = ("exclusive shelf", "shelf", "status", "bookshelf")
_DATE_READ_KEYS = ("date read", "read date", "finished", "date finished")
_TAG_KEYS = ("bookshelves", "tags", "shelves")


@dataclass(frozen=True)
class _Columns:
    """Which headers carry each field, in preference order (lowercased)."""

    title: tuple[str, ...]
    author: tuple[str, ...]
    isbn: tuple[str, ...]
    rating: tuple[str, ...]
    review: tuple[str, ...]
    status: tuple[str, ...]
    date_read: tuple[str, ...]
    date_started: tuple[str, ...]
    tags: tuple[str, ...]


_GENERIC_COLUMNS = _Columns(
    title=_TITLE_KEYS,
    author=_AUTHOR_KEYS,
    isbn=_ISBN_KEYS,
    rating=_RATING_KEYS,
    review=_REVIEW_KEYS,
    status=_STATUS_KEYS,
    date_read=_DATE_READ_KEYS,
    date_started=(),
    tags=_TAG_KEYS,
)

_COLUMNS = {
    FORMAT_GOODREADS: _GENERIC_COLUMNS,
    FORMAT_GENERIC: _GENERIC_COLUMNS,
    # `notes` is the reader's private note on the copy (rule 13: never a review).
    FORMAT_LIBIB: _Columns(
        title=("title",),
        author=("creators",),
        isbn=("ean_isbn13", "upc_isbn10"),
        rating=("rating",),
        review=("review",),
        status=("status",),
        date_read=("completed",),
        date_started=("began",),
        tags=("tags",),
    ),
    # No status column: it is derived from the reading dates (`_lt_status`).
    # `Comment` / `Private Comment` are notes, not the review.
    FORMAT_LIBRARYTHING: _Columns(
        title=("title",),
        author=("primary author",),
        isbn=("isbn",),
        rating=("rating",),
        review=("review",),
        status=(),
        date_read=("date read",),
        date_started=("date started",),
        tags=("tags",),
    ),
}


@dataclass
class ImportRow:
    title: str
    author: str | None = None
    isbn: str | None = None
    rating: int | None = None  # 1-5, or None when unrated
    review: str | None = None
    status: str | None = None  # a Kitabi status, or None
    date_read: str | None = None  # the export's own date string, or None
    tags: list[str] = field(default_factory=list)
    date_started: str | None = None  # Libib/LibraryThing only


def _clean_isbn(raw: str | None) -> str | None:
    """Goodreads wraps ISBNs as `="9780..."` and LibraryThing as `[9780...]`;
    strip that and any hyphens, and canonicalise to ISBN-13.

    Goodreads exports carry BOTH an `ISBN` (10) and an `ISBN13` column, and
    which one is populated varies row by row within a single file. Canonicalising
    here is what makes the catalogue lookup in import_.py an exact hit for either.
    """
    return isbn_util.canonical(raw)


def _clean_rating(raw: str | None) -> int | None:
    """Kitabi's stars are whole; Libib and LibraryThing allow halves ("4.5").
    A half rounds UP — truncating would turn a real 0.5 into "unrated"."""
    if not raw:
        return None
    try:
        value = int(float(raw) + 0.5)
    except (ValueError, OverflowError):
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


def _lt_status(date_read: str | None, date_started: str | None) -> str | None:
    """LibraryThing has no reading status — its `Collections` are the reader's
    own names ("Your library", "Graphic novels") — so the dates say it: a
    finish date is a read book, a start date alone is one being read."""
    if date_read:
        return "read"
    if date_started:
        return "reading"
    return None


def _first_last(name: str | None) -> str | None:
    """LibraryThing writes the primary author surname first ("Vijayan, O. V.").
    Only the plain one-comma shape is turned round; anything else is kept as
    written rather than guessed at."""
    if not name:
        return name
    parts = [p.strip() for p in name.split(",")]
    if len(parts) == 2 and all(parts):
        return f"{parts[1]} {parts[0]}"
    return name


def _clean_date(raw: str | None) -> str | None:
    """LibraryThing's tab-delimited export brackets its dates: `[2024-03-10]`."""
    if not raw:
        return None
    return raw.removeprefix("[").removesuffix("]").strip() or None


_GOODREADS_ARMOUR = re.compile(r'^="(.*)"$')


def _unwrap(value: str) -> str:
    """Strip Goodreads' `="…"` cell armour (it stops Excel eating leading zeros).

    An EMPTY armoured cell is `=""` — two characters, and therefore truthy. That
    is how an empty ISBN13 column silently shadowed a populated ISBN one in
    `_pick`, making the 10-digit column unreachable for every row that had only
    that: the import matched on title alone and missed books we had.
    """
    match = _GOODREADS_ARMOUR.match(value)
    return match.group(1).strip() if match else value


def _pick(row: dict[str, str], keys: tuple[str, ...]) -> str | None:
    """First non-empty value whose (lowercased) header matches one of `keys`."""
    lowered = {k.strip().lower(): _unwrap((v or "").strip()) for k, v in row.items() if k}
    for key in keys:
        if lowered.get(key):
            return lowered[key]
    return None


def is_goodreads(headers: list[str]) -> bool:
    lowered = {h.strip().lower() for h in headers}
    return "exclusive shelf" in lowered and "my rating" in lowered


def _format_of(headers: list[str]) -> str:
    lowered = {h.strip().lower() for h in headers}
    if is_goodreads(headers):
        return FORMAT_GOODREADS
    if "ean_isbn13" in lowered or "upc_isbn10" in lowered:
        return FORMAT_LIBIB
    if "primary author" in lowered:
        return FORMAT_LIBRARYTHING
    return FORMAT_GENERIC


def _reader(text: str) -> csv.DictReader:
    """LibraryThing offers its export tab-delimited as well as comma-separated,
    so the delimiter is read off the header line. A byte-order mark (Excel
    adds one on save) would otherwise glue itself to the first header."""
    text = text.lstrip("﻿")
    header = text.split("\n", 1)[0]
    delimiter = "\t" if header.count("\t") > header.count(",") else ","
    return csv.DictReader(io.StringIO(text), delimiter=delimiter)


def detect_format(text: str) -> str:
    """Which export this is: goodreads, libib, librarything, or generic."""
    return _format_of(_reader(text).fieldnames or [])


def parse_csv(text: str, limit: int = 2000) -> list[ImportRow]:
    """Parse a Goodreads, Libib, LibraryThing or generic book CSV into
    normalized rows. Rows without a title are skipped. Capped at `limit` rows."""
    reader = _reader(text)
    fmt = _format_of(reader.fieldnames or [])
    cols = _COLUMNS[fmt]
    rows: list[ImportRow] = []
    for raw in reader:
        if len(rows) >= limit:
            break
        # A Libib collection can hold films, music and games beside books; a
        # DVD of "Chemmeen" must not match the novel by title.
        if fmt == FORMAT_LIBIB and (_pick(raw, ("item_type",)) or "book").lower() != "book":
            continue
        title = _pick(raw, cols.title)
        if not title:
            continue
        tags_raw = _pick(raw, cols.tags)
        tags = [t.strip() for t in (tags_raw or "").split(",") if t.strip()] if tags_raw else []
        author = _pick(raw, cols.author)
        date_read = _clean_date(_pick(raw, cols.date_read))
        date_started = _clean_date(_pick(raw, cols.date_started))
        if fmt == FORMAT_LIBIB:
            status = _LIBIB_STATUS.get((_pick(raw, cols.status) or "").lower())
        elif fmt == FORMAT_LIBRARYTHING:
            author = _first_last(author)
            status = _lt_status(date_read, date_started)
        else:
            status = _map_status(_pick(raw, cols.status))
        rows.append(
            ImportRow(
                title=title,
                author=author,
                isbn=_clean_isbn(_pick(raw, cols.isbn)),
                rating=_clean_rating(_pick(raw, cols.rating)),
                review=_pick(raw, cols.review),
                status=status,
                date_read=date_read,
                tags=tags,
                date_started=date_started,
            )
        )
    return rows
