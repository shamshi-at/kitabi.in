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

**Two things are checked harder than the rest, because they are what make a
row a *book*** (owner, 3 Oct 2026: *"I don't want any books which has no valid
ISBN or name doesn't seem like a valid book"*). The number has to be a real
book number — right checksum, a book prefix, and not a placeholder someone
typed to get past a required field. And the title has to be the name of one
book: not a blank or a filler word, not a SKU, not markup, and not a product a
storefront happens to sell beside its books (a combo, a box set, a gift card).
A publisher's feed is a shop's catalogue, and a shop sells things that are not
books.

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

import html
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
#: A real name, of something that is not one book: a bundle, a box set, a gift
#: card. Separate from `title_not_a_title` because the two say different things
#: about a source — one is feeding us junk, the other is a shop selling
#: non-books, and only the second is expected.
FATAL_NOT_A_BOOK = "title_not_a_book"
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


#: A complete HTML character reference, semicolon included. `html.unescape`
#: alone also expands legacy *unterminated* names — `&not`, `&copy`, `&reg` —
#: which would turn `Why&nothing` into `Why¬hing`; only a terminated reference
#: is unambiguous enough to rewrite unattended.
_ENTITY = re.compile(r"&(?:#\d{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});")


def _plain(value: str | None) -> str | None:
    """`_text`, with HTML character references decoded.

    A storefront's JSON feed carries titles the way its pages print them:
    `MARIYA&#8230;VERUM MARIA` (mbibooks.com, 3 Oct 2026), `Simon &amp;
    Schuster`. Decoded here, once, rather than stored and shown to a reader.
    """
    cleaned = _text(value)
    if cleaned is None or "&" not in cleaned:
        return cleaned
    return _text(_ENTITY.sub(lambda m: html.unescape(m.group(0)), cleaned))


#: Words that fill a required field without naming anything. Whole-title
#: matches only: "The Test" and "Book of Longing" are books, "test" and "book"
#: are someone's form default.
_PLACEHOLDER_TITLES = frozenset(
    {
        "untitled",
        "unknown",
        "no title",
        "title",
        "test",
        "testing",
        "sample",
        "demo",
        "n/a",
        "na",
        "none",
        "null",
        "tbd",
        "tba",
        "coming soon",
        "book",
        "new book",
        "default title",
        "product",
    }
)
#: Tags, or a character reference that survived decoding.
_MARKUP = re.compile(r"<[A-Za-z/!][^>]*>|&(?:#\d+|#[xX][0-9a-fA-F]+|[A-Za-z]{2,});")
_URLISH = re.compile(r"https?://|\bwww\.", re.IGNORECASE)
#: Six or more digits and nothing else (bar separators) is a stock number or an
#: ISBN sitting in the wrong column. Shorter all-digit titles are left alone —
#: `1984`, `2666` and `300` are books.
_STOCK_NUMBER = re.compile(r"^[\d\s\-_/.#]*$")
#: One character, repeated: `xxxxx`, `-----`, `.....`.
_ONE_CHAR_REPEATED = re.compile(r"^(.)\1{3,}$", re.DOTALL)

#: What a shop adds to a title that is not part of it — measured on nine
#: publishers' storefront feeds, 3 Oct 2026. Each of these is a real book under
#: a name no catalogue should print, so the row is refused and the *adapter*
#: is what has to supply the clean title (a re-crawl re-screens it):
#:
#: - a format or edition label: `(Paperback)`, `GET EPIC SHIT DONE (Telugu
#:   Edition)`. Under rule 17 that belongs to the Edition, never the Work.
#: - a tagline after a pipe: `Musafir Cafe | Now a Netflix Series`. No title
#:   contains a pipe.
#: - a search-engine listing: `Booktopus Playtime Activity Book – Outer Space –
#:   Learning Activity Books for Kids 4+ Years – Early Learning…`.
_SHOP_LABEL = re.compile(
    r"""
      [(\[]\s*(?:paperback|hardcover|hardback|hb|pb|e-?book|audiobook)\s*[)\]]
    | \b(?:hindi|tamil|telugu|malayalam|kannada|marathi|bengali|gujarati|punjabi
          |odia|urdu|english|special|revised|illustrated|deluxe|collector'?s
          |anniversary|kindle|paperback|hardcover|kids|young\s+readers?)
      \s+edition\b
    | \|
    """,
    re.IGNORECASE | re.VERBOSE,
)
_SPACED_DASH = re.compile(r"\s[–—-]\s")
#: Three or more ` – ` breaks is a product listing, not a title and subtitle.
_LISTING_DASHES = 3
#: A title set entirely in capitals is a shop's display style (`MARANAVAMSAM`,
#: `IT ENDS WITH US`), and fixing it needs a judgement — which words are
#: acronyms, which are small — that an unattended pass should not make. Below
#: this many letters it is as likely an acronym that *is* the title: `SPQR`,
#: `NW`, `QB VII`.
_SHOUTING_MIN_LETTERS = 8

#: Things a publisher's shop sells that are not one book. Deliberately narrow,
#: and every alternative needs a digit or a second word, because the plain
#: words are all real titles: *A Bundle of Joy*, Conrad's *A Set of Six*, *Pack
#: of Lies*, *The Gift*. What it catches is what was actually in the feeds
#: (`Shabnam Noorjahan Combo 2 Books`, olivepublications.in, 3 Oct 2026).
_NOT_ONE_BOOK = re.compile(
    r"""
      \bcombo\b
    | \bbox(?:ed)?[\s-]?set\b
    | \bbooks?\s+set\b
    | \bset\s+of\s+\d+\b
    | \bpack\s+of\s+\d+\b
    | \bbundle\s+(?:of\s+\d+|pack|offer|deal)\b
    | \b(?:books?|combo|value)\s+bundle\b
    | \b\d+[\s-]books?\s+(?:set|combo|pack|bundle|collection)\b
    | \(\s*\d+\s*books?\s*\)
    | \b(?:set|collection)\s+of\s+\d+\s+books\b
    | \be?-?gift\s+(?:card|voucher|pack|hamper)\b
    | \(\s*sets?\s*\)
    | \b(?:wall|desk|table)\s+calendar\b
    | \b(?:calendar|diary|planner)\s+20\d\d\b
    | \b20\d\d\s+(?:calendar|diary|planner)\b
    """,
    re.IGNORECASE | re.VERBOSE,
)


def _title_refusal(title: str, publisher: str | None) -> str | None:
    """Why this cleaned title cannot be a book's, or None if it can.

    Script-agnostic: "has a letter or a digit" is asked of Unicode, so a
    Malayalam title is as much a title as a Latin one.
    """
    folded = " ".join(title.casefold().split())
    if not any(ch.isalnum() for ch in title):
        return FATAL_TITLE_JUNK  # punctuation only: "—", "???"
    if folded in _PLACEHOLDER_TITLES or _ONE_CHAR_REPEATED.match(folded):
        return FATAL_TITLE_JUNK
    if _MARKUP.search(title) or _URLISH.search(title):
        return FATAL_TITLE_JUNK
    if _STOCK_NUMBER.match(title) and sum(ch.isdigit() for ch in title) >= 6:
        return FATAL_TITLE_JUNK
    if publisher and folded == " ".join(publisher.casefold().split()):
        # The feed put the house's name in the title column.
        return FATAL_TITLE_JUNK
    if _NOT_ONE_BOOK.search(title):
        # Asked before the shop-styling checks below: `GURU COMBO` is not a
        # book however it is capitalised, and saying so is the useful verdict.
        return FATAL_NOT_A_BOOK
    if _SHOP_LABEL.search(title) or len(_SPACED_DASH.findall(title)) >= _LISTING_DASHES:
        return FATAL_TITLE_JUNK
    cased = [ch for ch in title if ch.isupper() or ch.islower()]
    if len(cased) >= _SHOUTING_MIN_LETTERS and not any(ch.islower() for ch in cased):
        # Scripts without case (Malayalam, Devanagari…) have no cased letters
        # at all, so this never touches them.
        return FATAL_TITLE_JUNK
    return None


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
#: …and one slice of 979 is not books either: `979-0` is the ISMN range, for
#: printed music. A score has a valid check digit and a Bookland prefix and is
#: still not a book.
_ISMN_PREFIX = "9790"
#: The number every example, form default and test fixture uses. It passes the
#: checksum, which is exactly why it turns up in real feeds.
_DUMMY_ISBNS = frozenset({"9781234567897"})


def _placeholder_isbn(isbn13: str) -> bool:
    """A number typed to satisfy a required field rather than to name a book:
    the well-known dummy, or one whose whole body is a single repeated digit
    (`978-0-00-000000-2`, `978-1-11-111111-6`)."""
    return isbn13 in _DUMMY_ISBNS or len(set(isbn13[3:12])) == 1


def _valid_isbn13(raw: str | None) -> str | None:
    """A genuine ISBN-13, or None. Stricter than `services/isbn` on purpose.

    The mod-10 check digit is only one of the things that make an ISBN-13 an
    ISBN — the prefix has to be a book prefix (not `979-0`, which is sheet
    music), and the number has to be one somebody was actually assigned rather
    than a placeholder that happens to check out. `9189376880780` — a real
    number off a real publisher's product page (mbibooks.com, 9 Sep 2026) —
    passes the checksum by coincidence and is still not an ISBN, because no
    `918` prefix exists. One in ten wrong numbers
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
    if folded.startswith(_ISMN_PREFIX) or _placeholder_isbn(folded):
        return None
    return folded


def screen(candidate: Candidate) -> Screened:
    """Clean what can be cleaned, then decide. Never raises."""
    missing: list[str] = []
    fatal: list[str] = []

    # --- title (and the subtitle a MARC title may be hiding) ---------------
    raw_title = _plain(candidate.title)
    title: str | None = None
    subtitle = _plain(candidate.subtitle)
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
        elif refusal := _title_refusal(title, _plain(candidate.publisher)):
            fatal.append(refusal)

    # --- authors ----------------------------------------------------------
    # Un-inversion is `review` risk in the cleanup script because it reorders a
    # human name and a *bulk* pass over rows nobody has looked at wants an eye
    # on it. Here it applies to one incoming record that does not exist yet:
    # nothing is being overwritten, and the alternative is importing
    # `Basheer, Vaikom Muhammad` and needing the review pass anyway.
    authors: list[str] = []
    for raw in candidate.authors:
        name = _plain(raw)
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
        marc_cleanup.clean_name(_plain(candidate.publisher) or "")
        if _plain(candidate.publisher)
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
