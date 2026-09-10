"""The completeness gate: a candidate book is complete, or it is not created.

This is the rule the whole daily intake is built to enforce (owner, 9 Sep 2026:
*"I don't want any unwanted records to be created"*, and *"no more adjustment
records"*). Both halves of that are one idea — the catalogue should never hold
a row that something later has to come back and fix — and the way to get it is
to decide at the door, once, with a pure function that can be tested directly
rather than inferred from what ended up in the database.

Two kinds of "no", and the difference matters:

- **missing** — a field this source didn't supply. The candidate waits; another
  source may fill it. Nothing is wrong with the book.
- **fatal** — this record should not become a book at all. A MARC supplied
  heading (`[South Asia pamphlet collection.`) is not a title, and un-bracketing
  it would make it *look* more legitimate without making it more true
  (`services/marc_cleanup`'s own rule). These are never retried.

**Cleaning happens here, not afterwards.** `marc_cleanup` already knows how to
turn cataloguing punctuation into reader-facing text; running it at intake is
what makes `etl/09_marc_cleanup.py` unnecessary for everything this pipeline
creates, instead of necessary again. The acceptance test for that claim is in
docs/catalog-intake-plan.md §5 (P6): re-plan `09` after a month of intake and
it must report zero changes against rows this job made.

Pure — no ORM, no I/O, no settings. Duplicate detection is *not* here: whether
the catalogue already holds this ISBN is a database question and lives in
`intake_service`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, replace

from app.services import isbn as isbn_util
from app.services import marc_cleanup

# Absurdity bounds. Not style rules — a title of 600 characters is a pasted
# description and a page count of 40,000 is a parse error, and either one is a
# row a human would have to come back and fix.
MAX_TITLE = 300
MAX_SUBTITLE = 300
MAX_NAME = 160
MAX_PAGE_COUNT = 20_000
MAX_COVER_URL = 600

#: The five fields that make a record worth having. Ordered as a reader reads
#: a book page, which is also the order the queue reports them in.
REQUIRED = ("title", "authors", "publisher", "isbn", "cover_url")

# --- reasons ---------------------------------------------------------------
# Stable strings: written into `catalog_intake.missing` and read back by the
# console and by re-screening. Never rename one in place.
MISSING_TITLE = "title"
MISSING_AUTHORS = "authors"
MISSING_PUBLISHER = "publisher"
MISSING_ISBN = "isbn"
MISSING_COVER = "cover_url"
MISSING_LANGUAGE = "language"
#: An ISBN was supplied and is not one. Distinct from `isbn` so the queue can
#: tell "this source has no number for it" from "this source has a bad one" —
#: the second is worth reporting upstream, the first is just a gap.
INVALID_ISBN = "isbn_invalid"

FATAL_TITLE_JUNK = "title_not_a_title"
FATAL_NAME_JUNK = "author_name_unusable"
FATAL_OVERSIZE = "field_oversize"
FATAL_COVER_SCHEME = "cover_not_https"

#: `marc_cleanup` flags that mean "a human would have to judge this" — which is
#: exactly what an unattended pipeline must not do.
_FATAL_TITLE_FLAGS = frozenset({marc_cleanup.BRACKETED_TITLE, marc_cleanup.UNBALANCED_BRACKET})
_FATAL_NAME_FLAGS = frozenset({marc_cleanup.MULTI_COMMA_NAME, marc_cleanup.UNBALANCED_BRACKET})


@dataclass(frozen=True)
class Candidate:
    """One book as a source adapter found it, before any judgement.

    Deliberately flat and JSON-shaped: this is what `catalog_intake.payload`
    stores, so a gate change can be replayed against what the source actually
    said without re-crawling it.
    """

    source: str
    source_key: str
    title: str
    authors: tuple[str, ...] = ()
    publisher: str | None = None
    isbn: str | None = None
    cover_url: str | None = None
    language: str | None = None
    subtitle: str | None = None
    description: str | None = None
    page_count: int | None = None
    first_publish_year: int | None = None
    back_cover_url: str | None = None
    #: Catalogue provenance — what goes into `works.external_source` /
    #: `works.external_id`. Deliberately separate from `source`/`source_key`,
    #: which name the *adapter* that found the book. Several adapters can read
    #: one upstream catalogue, and the existing `etl/` seed already stamped
    #: 1,428 works with `openlibrary` + the OL work key; an adapter that
    #: invented its own provenance string would fail to recognise them and
    #: create a second Work for every one.
    external_source: str | None = None
    external_id: str | None = None

    @property
    def provenance(self) -> tuple[str, str]:
        """`(external_source, external_id)` — falling back to the adapter's own
        identity when a source has no upstream catalogue of its own."""
        return (self.external_source or self.source, self.external_id or self.source_key)

    def to_payload(self) -> dict:
        return {
            "source": self.source,
            "source_key": self.source_key,
            "title": self.title,
            "authors": list(self.authors),
            "publisher": self.publisher,
            "isbn": self.isbn,
            "cover_url": self.cover_url,
            "language": self.language,
            "subtitle": self.subtitle,
            "description": self.description,
            "page_count": self.page_count,
            "first_publish_year": self.first_publish_year,
            "back_cover_url": self.back_cover_url,
            "external_source": self.external_source,
            "external_id": self.external_id,
        }

    @classmethod
    def from_payload(cls, payload: dict) -> Candidate:
        data = dict(payload)
        data["authors"] = tuple(data.get("authors") or ())
        known = cls.__dataclass_fields__.keys()
        return cls(**{k: v for k, v in data.items() if k in known})


@dataclass(frozen=True)
class Screened:
    """The verdict, plus the cleaned candidate when there is one."""

    candidate: Candidate
    missing: tuple[str, ...] = ()
    fatal: tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return not self.missing and not self.fatal

    @property
    def rejected(self) -> bool:
        return bool(self.fatal)


def _text(value: str | None) -> str | None:
    cleaned = (value or "").strip()
    return cleaned or None


#: Trailing separators a name should never end in. `marc_cleanup.clean_name`
#: strips a terminal period and a MARC date suffix but deliberately not these,
#: because a comma *inside* a publisher name is usually load-bearing (55 of
#: 1,021 seeded names are departments and addresses). A comma at the very
#: *end* never is — `Juggernaut Books Pty,` came back from OpenLibrary exactly
#: like that on 11 Sep 2026, and a reader would see the comma on the page.
_TRAILING_JUNK = re.compile(r"[\s,;:/=\-]+$")


def _tidy_name(name: str | None) -> str | None:
    cleaned = _text(name)
    return _text(_TRAILING_JUNK.sub("", cleaned)) if cleaned else None


def _https(url: str | None) -> str | None:
    """A cover we are willing to point a reader's phone at.

    https only — the app and the edge proxy both refuse anything else, so an
    http URL is a cover that will render as a blank box rather than a picture.
    """
    cleaned = _text(url)
    if not cleaned or len(cleaned) > MAX_COVER_URL:
        return None
    return cleaned if cleaned.lower().startswith("https://") else None


#: The only two prefixes the Bookland EAN range assigns to books. Everything
#: else is some other GS1 product, whatever its check digit says.
_ISBN13_PREFIXES = ("978", "979")


def _valid_isbn13(raw: str | None) -> str | None:
    """A genuine ISBN-13, or None. Stricter than `services/isbn` on purpose.

    The mod-10 check digit is only one of the two things that make an ISBN-13
    an ISBN. `9189376880780` — a real number off a real publisher's product
    page (mbibooks.com, 9 Sep 2026) — passes the checksum by coincidence and is
    still not an ISBN, because no `918` prefix exists. One in ten wrong numbers
    passes a mod-10 check, so on a pipeline that promotes unattended the
    checksum alone is not a gate.

    This lives here rather than in `services/isbn` because that module's
    leniency is a deliberate, documented product decision for reader-typed
    input, and tightening it there would start rejecting numbers readers have
    already stored.
    """
    folded = isbn_util.to_isbn13(raw)
    if folded is None or not folded.startswith(_ISBN13_PREFIXES):
        return None
    return folded


def screen(candidate: Candidate) -> Screened:
    """Clean what can be cleaned, then decide. Never raises."""
    missing: list[str] = []
    fatal: list[str] = []

    # --- title (and the subtitle a MARC title may be hiding) ---------------
    raw_title = _text(candidate.title)
    title: str | None = None
    subtitle = _text(candidate.subtitle)
    if raw_title is None:
        missing.append(MISSING_TITLE)
    else:
        fix = marc_cleanup.clean_work(raw_title, subtitle, tuple(candidate.authors))
        if _FATAL_TITLE_FLAGS.intersection(fix.flags):
            fatal.append(FATAL_TITLE_JUNK)
        title = _text(fix.title)
        subtitle = _text(fix.subtitle)
        if title is None:
            missing.append(MISSING_TITLE)
        elif len(title) > MAX_TITLE or (subtitle and len(subtitle) > MAX_SUBTITLE):
            fatal.append(FATAL_OVERSIZE)

    # --- authors ----------------------------------------------------------
    # Un-inversion is `review` risk in the cleanup script because it reorders a
    # human name and a *bulk* pass over rows nobody has looked at wants an eye
    # on it. Here it applies to one incoming record that does not exist yet:
    # nothing is being overwritten, and the alternative is importing
    # `Basheer, Vaikom Muhammad` and needing the review pass anyway.
    authors: list[str] = []
    for raw in candidate.authors:
        name = _text(raw)
        if name is None:
            continue
        fix = marc_cleanup.clean_name(name, uninvert=True)
        if _FATAL_NAME_FLAGS.intersection(fix.flags):
            fatal.append(FATAL_NAME_JUNK)
            continue
        cleaned = _tidy_name(fix.name)
        if cleaned is None:
            continue
        if len(cleaned) > MAX_NAME:
            fatal.append(FATAL_OVERSIZE)
            continue
        if cleaned not in authors:
            authors.append(cleaned)
    if not authors:
        missing.append(MISSING_AUTHORS)

    # --- publisher --------------------------------------------------------
    publisher_fix = (
        marc_cleanup.clean_name(_text(candidate.publisher) or "")
        if _text(candidate.publisher)
        else None
    )
    publisher = _tidy_name(publisher_fix.name) if publisher_fix else None
    if publisher is None:
        missing.append(MISSING_PUBLISHER)
    elif len(publisher) > MAX_NAME:
        fatal.append(FATAL_OVERSIZE)
        publisher = None

    # --- ISBN -------------------------------------------------------------
    # Checksum, not shape. `9189376880780` is thirteen digits and cannot be an
    # ISBN (no 918 prefix exists); a publisher's own storefront really does
    # emit one now and then (measured on mbibooks.com, 9 Sep 2026).
    #
    # `to_isbn13`, deliberately NOT `canonical`. `canonical` falls back to the
    # cleaned input when the checksum fails, and its docstring is right about
    # why: on the reader-facing write path, dropping a mis-keyed number would
    # destroy the only edition identifier a contributor has. That reasoning
    # does not transfer here. Nobody is typing this, nothing is lost by waiting
    # for a better source, and the requirement on this pipeline is that every
    # record it creates carries a *valid* ISBN. `to_isbn13` returns None on a
    # bad checksum and folds a valid ISBN-10 up to the 13 we store.
    raw_isbn = _text(candidate.isbn)
    isbn: str | None = None
    if raw_isbn is None:
        missing.append(MISSING_ISBN)
    else:
        isbn = _valid_isbn13(raw_isbn)
        if isbn is None:
            # Dropped rather than stored: a number that isn't an ISBN must not
            # sit in the payload looking like one. Reported separately from a
            # plain absence so the queue stays honest about which it is.
            missing.append(INVALID_ISBN)

    # --- cover ------------------------------------------------------------
    cover_url = _https(candidate.cover_url)
    if cover_url is None:
        if _text(candidate.cover_url):
            fatal.append(FATAL_COVER_SCHEME)
        else:
            missing.append(MISSING_COVER)

    # --- language ---------------------------------------------------------
    # Required, though not in REQUIRED: browse, the language chips and the
    # public hubs all key off it, and a row without one is a row someone fills
    # in later — which is the thing this gate exists to prevent.
    language = _text(candidate.language)
    if language is None:
        missing.append(MISSING_LANGUAGE)

    page_count = candidate.page_count
    if page_count is not None and not (0 < page_count <= MAX_PAGE_COUNT):
        page_count = None

    cleaned_candidate = replace(
        candidate,
        title=title or candidate.title,
        subtitle=subtitle,
        authors=tuple(authors),
        publisher=publisher,
        isbn=isbn,
        cover_url=cover_url,
        language=language,
        back_cover_url=_https(candidate.back_cover_url),
        page_count=page_count,
        description=_text(candidate.description),
    )
    # A fatal verdict makes the missing list noise — the row is not waiting for
    # anything, it is refused.
    return Screened(
        candidate=cleaned_candidate,
        missing=() if fatal else tuple(dict.fromkeys(missing)),
        fatal=tuple(dict.fromkeys(fatal)),
    )
