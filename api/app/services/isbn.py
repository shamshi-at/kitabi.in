"""ISBN-10 / ISBN-13 reconciliation.

The catalogue stores whatever form a contributor typed, a scanner read, or
OpenLibrary answered with. Those are not interchangeable strings: the same book
is 8126403454 on the back of a 2005 printing and 9788126403455 on a 2019 one,
and a lookup written as `Edition.isbn == query` finds one and misses the other.
That is invisible until a reader pastes the number off a book they are holding
and the site tells them we have never heard of it.

So every ISBN entering the system is reduced to a canonical form (ISBN-13 when
it can be derived) on the way in, and every lookup expands to `variants()` on
the way out — because normalising new writes does nothing for the rows already
stored, and a backfill can never be assumed to have reached every one of them.
Both halves are needed; neither alone closes the gap.

Pure and dependency-free — no ORM, no I/O — so the arithmetic can be tested
directly rather than inferred from query results.
"""

from __future__ import annotations

import re

# The two shapes, AFTER cleaning: 9 digits + a check character (digit or X), or
# 13 digits. Note the X is only ever valid in the final position of an ISBN-10;
# it is the character used when the check value is 10.
_ISBN10_RE = re.compile(r"^[0-9]{9}[0-9X]$")
_ISBN13_RE = re.compile(r"^[0-9]{13}$")

# ISBN-13s beginning 979 have no ISBN-10 equivalent — the 979 range was created
# precisely because the 978 space ran out, so there is nothing to map back to.
_CONVERTIBLE_PREFIX = "978"


def clean(raw: str | None) -> str | None:
    """Strip formatting and return the bare ISBN, or None if it isn't one.

    Accepts the forms people actually paste: hyphenated ("978-81-264-0345-5"),
    spaced, prefixed ("ISBN: 8126403454"), and Goodreads' CSV armour (`="978…"`).
    Only the shape is checked here, not the checksum — see `variants` for why a
    checksum-invalid ISBN must still be looked up rather than rejected.
    """
    if not isinstance(raw, str):
        return None
    stripped = re.sub(r"[^0-9Xx]", "", raw).upper()
    if _ISBN10_RE.match(stripped) or _ISBN13_RE.match(stripped):
        return stripped
    return None


def looks_like_isbn(raw: str | None) -> bool:
    """Is this query an ISBN rather than a title? Shape only.

    Used to route a search: a 13-digit string is never a title, so it takes the
    exact-match path instead of being handed to the fuzzy matcher, where
    trigram similarity on digits produces confident nonsense.
    """
    return clean(raw) is not None


def is_valid_isbn10(value: str | None) -> bool:
    """Mod-11 checksum: sum of digit x (10 - position) must be divisible by 11,
    with X standing in for the check value 10."""
    cleaned = clean(value)
    if cleaned is None or not _ISBN10_RE.match(cleaned):
        return False
    total = 0
    for index, char in enumerate(cleaned):
        digit = 10 if char == "X" else int(char)
        total += digit * (10 - index)
    return total % 11 == 0


def is_valid_isbn13(value: str | None) -> bool:
    """Mod-10 checksum with alternating 1/3 weights (the EAN-13 rule)."""
    cleaned = clean(value)
    if cleaned is None or not _ISBN13_RE.match(cleaned):
        return False
    total = sum((1 if i % 2 == 0 else 3) * int(d) for i, d in enumerate(cleaned))
    return total % 10 == 0


def _isbn13_check_digit(first_twelve: str) -> str:
    total = sum((1 if i % 2 == 0 else 3) * int(d) for i, d in enumerate(first_twelve))
    return str((10 - total % 10) % 10)


def _isbn10_check_char(first_nine: str) -> str:
    total = sum(int(d) * (10 - i) for i, d in enumerate(first_nine))
    remainder = (11 - total % 11) % 11
    return "X" if remainder == 10 else str(remainder)


def to_isbn13(value: str | None) -> str | None:
    """The ISBN-13 for a checksum-valid ISBN-10: prepend 978, drop the old
    check character, recompute. Returns an ISBN-13 input unchanged (also only
    when valid), so callers can pass either form without branching."""
    cleaned = clean(value)
    if cleaned is None:
        return None
    if _ISBN13_RE.match(cleaned):
        return cleaned if is_valid_isbn13(cleaned) else None
    if not is_valid_isbn10(cleaned):
        return None
    body = _CONVERTIBLE_PREFIX + cleaned[:9]
    return body + _isbn13_check_digit(body)


def to_isbn10(value: str | None) -> str | None:
    """The ISBN-10 for a checksum-valid, 978-prefixed ISBN-13. None for a 979
    (no equivalent exists) or for anything that fails its checksum."""
    cleaned = clean(value)
    if cleaned is None:
        return None
    if _ISBN10_RE.match(cleaned):
        return cleaned if is_valid_isbn10(cleaned) else None
    if not is_valid_isbn13(cleaned) or not cleaned.startswith(_CONVERTIBLE_PREFIX):
        return None
    body = cleaned[3:12]
    return body + _isbn10_check_char(body)


def canonical(raw: str | None) -> str | None:
    """The form to STORE: ISBN-13 whenever it can be derived, else the cleaned
    input verbatim.

    Falling back to the input rather than rejecting it is deliberate. Real
    catalogue data contains ISBNs that fail their checksum — mis-keyed by a
    contributor, misprinted by a publisher, or mangled upstream — and dropping
    those loses the only edition identifier we have. They are stored as given
    and still found, because `variants` looks up the literal form too.
    """
    cleaned = clean(raw)
    if cleaned is None:
        return None
    return to_isbn13(cleaned) or cleaned


def normalize_for_storage(raw: str | None) -> str | None:
    """Canonicalize what we recognise as an ISBN; leave anything else exactly
    as given.

    This is the write-path entry point (a Pydantic validator on every schema
    carrying an ISBN), so it must never destroy a contributor's input. A string
    that isn't ISBN-shaped is passed through untouched rather than nulled: it is
    far more likely to be a half-typed number the reader is still editing than
    something we should silently discard on their behalf.
    """
    if not isinstance(raw, str):
        return raw
    return canonical(raw) or raw


def variants(raw: str | None) -> list[str]:
    """Every stored form that could denote this ISBN, best-known form first.

    A lookup matches against ALL of these, which is what makes a search for a
    book's ISBN-10 find the row catalogued under its ISBN-13. The literal
    cleaned input is always included, even when the checksum fails, so a
    lookup can still reach a row holding that exact bad value — the alternative
    is data we accepted on write and can never retrieve.

    Empty list for a non-ISBN, so a caller can treat "no variants" as "don't
    take the ISBN path" without a second shape check.
    """
    cleaned = clean(raw)
    if cleaned is None:
        return []
    out = [cleaned]
    for alternative in (to_isbn13(cleaned), to_isbn10(cleaned)):
        if alternative and alternative not in out:
            out.append(alternative)
    return out
