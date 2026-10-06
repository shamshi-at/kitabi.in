"""Intake adapter: Kerala Book Store (keralabookstore.com) — the Malayalam breadth.

The plan's P4 ("Malayalam breadth: DC Books") found the gap and could not close
it: the one shop that lists DC Books is a client-side app whose catalogue API
lives under a path its `robots.txt` disallows, and the open Malayalam
storefronts are single publishers' own shops. This is the other kind of source:
a multi-publisher retailer — 28,673 book pages in its sitemap, from some
hundred Kerala houses — that happens to render every book as plain HTML with
schema.org microdata.

Measured 6 Oct 2026 on twelve pages (the newest six and six at random): every
one carried a **title and author in Malayalam script**, the publisher, a
13-digit ISBN, the language, the page count and a front cover. That is the whole
completeness gate from one request, in the book's own script — the field the
romanized storefronts never have (`title_script`) and the one the gate holds the
most books on. The retailer's `<title>` repeats it all in a sentence, but the
microdata is what is read: it is what a template change is least likely to move.

**What this does and does not claim.** Facts about a book — its title, author,
publisher and number — are not the shop's to own, and the page is a public one
that `robots.txt` leaves open to an agent it has not named. The cover is a
publisher's, served by the retailer; the intake copies it to our own bucket
exactly as it does for a publisher's own shop, which is a decision the owner
made about publishers' shops and has not yet made about a retailer's. That is
why nothing here runs until `catalog_intake_keralabookstore_pages` is set.

**Polite.** The shop's `robots.txt` names a `Crawl-delay: 10` for a few bots and
none for anyone else; ten seconds is the delay it states, so ten seconds is the
pace. Identified by the job's User-Agent, `robots.txt` asked per page, and only
the shop's own host.

**An author's name in the wrong script is not usable.** The shop writes every
author in Malayalam script — an English book's too (4 of the 4 English pages in
the sample; the first preview showed `Dhanushkodi When the Sea Came Ashore` by
`മാത്യു ജോസഫ് തെക്കേമുറിയിൽ`). The catalogue spells an English book's author in
Latin letters, and `catalogue_spelling` only recognises a name in its own
script, so the book would have made a second author row for someone who writes
in English. On a page whose language is not Malayalam the author is therefore
dropped and the gate holds the book for `authors`; the English houses and
OpenLibrary are the sources that spell those names.

**One placeholder to refuse.** About one page in ten carries an ISBN beginning
`9780000` — a thirteen-digit number with a correct check digit, minted by the
shop for books it holds no number for (6 of 60 sampled pages, the newest ids
among them, so it is not a legacy of the old catalogue; another 6 had no number
at all). It passes the gate's checksum and is not a number any book has; kept,
it would be the key two different books collide on. It is dropped here, so the
gate reports the honest `isbn` gap instead.

**Measured on 60 pages, 6 Oct 2026** (the newest 20 and 40 at random): 44
complete from one request (73%) — 12 held for an ISBN, 4 for an English book's
author (above), one each for a publisher and a native title — and, asked of
production read-only, 29 would be new books, 15 are books we already have, 16
wait. 55 of 60 titles and authors
were in Malayalam script; 20 were Mathrubhumi's own list, 5 DC Books', the rest
some thirty other houses.

Discovery only, like the other adapters: nothing here writes a table.
"""

from __future__ import annotations

import asyncio
import html
import logging
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from urllib import robotparser
from urllib.parse import urlsplit

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogIntake
from app.services.intake_gate import Candidate
from app.services.intake_storefront import MAX_PAGE_BYTES, _blurb, _text

logger = logging.getLogger(__name__)

#: The adapter's name, written into `catalog_intake.source`.
SOURCE = "keralabookstore"
HOST = "keralabookstore.com"
SITEMAP_URL = f"https://{HOST}/sitemap.xml"

#: Between page reads. The shop's own stated crawl delay (see the module
#: docstring), applied to us although it names only other agents.
PAUSE_SECONDS = 10.0

#: The sitemap is one 5 MB file; a response far beyond that is not it.
MAX_SITEMAP_BYTES = 12_000_000

#: Consecutive failed reads that mean "the shop is down or refusing us tonight".
MAX_CONSECUTIVE_FAILURES = 4

#: `https://keralabookstore.com/book/anaswara-smaranakal/3/`
_BOOK_URL = re.compile(r"^https://keralabookstore\.com/book/[^/\s]+/(\d+)/$")
_LOC = re.compile(r"<loc>\s*([^<\s]+)\s*</loc>")

_TITLE = re.compile(r'<h1[^>]*itemprop="name"[^>]*>(.*?)</h1>', re.S)
_AUTHOR_BLOCK = re.compile(r'itemprop="author"[^>]*>(.*?)</h2>', re.S)
_NAME_SPAN = re.compile(r'<span itemprop="name">(.*?)</span>', re.S)
_PUBLISHER = re.compile(r'itemprop="publisher"[^>]*>.*?<span itemprop="name">(.*?)</span>', re.S)
_ISBN = re.compile(r'itemprop="isbn"[^>]*>\s*([0-9Xx\- ]{10,17}?)\s*<')
_LANGUAGE = re.compile(r'itemprop="inLanguage"[^>]*>.*?<span itemprop="name">(.*?)</span>', re.S)
_PAGES = re.compile(r'itemprop="numberOfPages"[^>]*>\s*(\d{1,5})\s*<')
_FORMAT = re.compile(r'itemprop="bookFormat"\s+content="https?://schema\.org/([A-Za-z]+)"')
_IMAGE = re.compile(r'<img[^>]*itemprop="image"[^>]*src="(https://[^"]+)"')
_DESCRIPTION = re.compile(r'itemprop="description"[^>]*>(.*?)</(?:div|p|span)>', re.S)

#: ISBN-13s the shop mints for books it has no number for (see the docstring).
_PLACEHOLDER_ISBN_PREFIX = "9780000"
#: The shop opens a description with its own label and the title's romanization
#: (`Book Name in English : Thirikevaranavatha Patha`). A label, not the blurb.
_MALAYALAM = re.compile(r"[\u0d00-\u0d7f]")
_NAME_IN_ENGLISH = re.compile(r"\A\s*Book Name in English\s*:[^\n]*\n*", re.I)


@dataclass(frozen=True)
class Listing:
    """One book page named by the sitemap."""

    book_id: int
    url: str


def parse_sitemap(xml: str) -> list[Listing]:
    """Every book page in the sitemap, newest id first.

    Ids are handed out in order, so the highest are the newest books — the same
    "new releases first" the storefront adapters get from a feed that is sorted
    by date. Anything that is not a book page (the home page, the lists) and
    anything not on the shop's own host is ignored.
    """
    found: dict[int, str] = {}
    for loc in _LOC.findall(xml):
        match = _BOOK_URL.match(html.unescape(loc))
        if match:
            found.setdefault(int(match.group(1)), match.group(0))
    return [Listing(book_id, found[book_id]) for book_id in sorted(found, reverse=True)]


def _clean(fragment: str | None) -> str | None:
    value = _text(fragment)
    return value or None


def _isbn(raw: str | None) -> str | None:
    digits = re.sub(r"[^0-9Xx]", "", raw or "")
    if not digits or digits.startswith(_PLACEHOLDER_ISBN_PREFIX):
        return None
    return digits


def parse_page(page: str, url: str, book_id: int) -> Candidate:
    """One book page as a candidate. Never raises on a page that is not one:
    what cannot be read is left empty and the gate says what is missing."""
    title = _clean(_TITLE.search(page).group(1)) if _TITLE.search(page) else None

    authors: list[str] = []
    for block in _AUTHOR_BLOCK.findall(page):
        for name in _NAME_SPAN.findall(block):
            if cleaned := _clean(name):
                authors.append(cleaned)

    publisher = _clean(m.group(1)) if (m := _PUBLISHER.search(page)) else None
    language = _clean(m.group(1)) if (m := _LANGUAGE.search(page)) else None
    isbn = _isbn(m.group(1)) if (m := _ISBN.search(page)) else None
    pages = int(m.group(1)) if (m := _PAGES.search(page)) else None
    fmt = m.group(1) if (m := _FORMAT.search(page)) else None
    cover = m.group(1) if (m := _IMAGE.search(page)) else None
    blurb = _blurb(m.group(1)) if (m := _DESCRIPTION.search(page)) else None
    if blurb:
        blurb = _NAME_IN_ENGLISH.sub("", blurb).strip() or None

    if (
        language
        and language.casefold() != "malayalam"
        and any(_MALAYALAM.search(a) for a in authors)
    ):
        authors = (
            []
        )  # see the module docstring: not the script the catalogue spells this book's author in

    return Candidate(
        source=SOURCE,
        source_key=str(book_id),
        external_source=SOURCE,
        external_id=str(book_id),
        source_url=url,
        title=title or "",
        # Labelled "Author" by the shop, so several names are several authors
        # (as they are on Mathrubhumi's own pages).
        authors=tuple(dict.fromkeys(authors)),
        publisher=publisher,
        isbn=isbn,
        cover_url=cover,
        language=language,
        description=blurb,
        page_count=pages,
        format=fmt,
    )


async def read_robots(client: httpx.AsyncClient) -> robotparser.RobotFileParser | None:
    """The shop's robots.txt, parsed — or None if it could not be read (the
    shop is then left alone tonight, as for every other source)."""
    rules = robotparser.RobotFileParser()
    try:
        response = await client.get(f"https://{HOST}/robots.txt")
    except httpx.HTTPError:
        return None
    if response.status_code in (404, 410):
        rules.parse([])
        return rules
    if response.status_code >= 400:
        return None
    rules.parse(response.text.splitlines())
    return rules


async def listings(client: httpx.AsyncClient) -> list[Listing] | None:
    """The shop's book pages, newest first — or None if the sitemap could not
    be read tonight."""
    try:
        response = await client.get(SITEMAP_URL)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("intake/%s: sitemap failed: %s", SOURCE, exc)
        return None
    if len(response.content) > MAX_SITEMAP_BYTES:
        logger.warning("intake/%s: sitemap is %s bytes — not read", SOURCE, len(response.content))
        return None
    return parse_sitemap(response.text)


async def staged_ids(db: AsyncSession) -> set[int]:
    """Which book ids are already in the staging table, whatever state."""
    keys = (
        (await db.execute(select(CatalogIntake.source_key).where(CatalogIntake.source == SOURCE)))
        .scalars()
        .all()
    )
    return {int(k) for k in keys if k.isdigit()}


def unstaged(found: Iterable[Listing], staged: set[int], limit: int) -> list[Listing]:
    """The next `limit` pages to read: the newest ones not yet staged."""
    out: list[Listing] = []
    for listing in found:
        if listing.book_id not in staged:
            out.append(listing)
            if len(out) >= limit:
                break
    return out


def owns(url: str) -> bool:
    """A page is only ever fetched from the shop's own host: the URL came out
    of a file we downloaded, and this runs inside our network."""
    parts = urlsplit(url)
    return parts.scheme == "https" and (parts.hostname or "").removeprefix("www.") == HOST


async def read_pages(
    client: httpx.AsyncClient,
    todo: Sequence[Listing],
    *,
    may_fetch=None,  # noqa: ANN001 — Callable[[str], bool]
    pause: float | None = None,
) -> list[Candidate]:
    """Read each page and return what it said, as candidates.

    A page that cannot be read costs itself; four in a row end the night's
    reading, because that is a shop that is down or has stopped answering us.
    """
    # Read at call time, not bound at definition, so the pace is one constant
    # that a test can set rather than a default it has to reach into.
    pause = PAUSE_SECONDS if pause is None else pause
    out: list[Candidate] = []
    failures = 0
    for listing in todo:
        if not owns(listing.url) or (may_fetch is not None and not may_fetch(listing.url)):
            continue
        try:
            response = await client.get(listing.url, follow_redirects=True)
        except httpx.HTTPError:
            response = None
        if pause:
            await asyncio.sleep(pause)
        if response is None or response.status_code >= 500 or response.status_code == 429:
            failures += 1
            if failures >= MAX_CONSECUTIVE_FAILURES:
                logger.warning(
                    "intake/%s: %s failures in a row — stopping tonight", SOURCE, failures
                )
                break
            continue
        failures = 0
        if response.status_code in (404, 410):
            # Gone for good. Staged as a book with nothing on it, so the gate
            # records it as held for a title and no night asks about it again —
            # at ten seconds a page, a dead address at the head of the list
            # would otherwise be re-read every night for ever.
            out.append(parse_page("", listing.url, listing.book_id))
            continue
        if response.status_code != 200 or len(response.content) > MAX_PAGE_BYTES:
            continue  # refused or not a book page: left unstaged and asked about again
        try:
            out.append(parse_page(response.text, listing.url, listing.book_id))
        except Exception:  # noqa: BLE001 — a page we cannot read is a page with nothing
            logger.warning("intake/%s: could not read page %s", SOURCE, listing.url)
    return out
