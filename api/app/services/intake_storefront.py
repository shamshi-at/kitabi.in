"""Intake adapters: publishers' own storefronts — where new releases come from.

OpenLibrary is a backlist source. Measured 3 Oct 2026, it lists **no** 2026
title for Penguin Random House India or HarperCollins India and none in any
year for Mathrubhumi, so a book published this week cannot arrive through
`intake_openlibrary`. It arrives on its publisher's own site first, and most
Indian publishers' sites are a WooCommerce shop whose Store API lists every
product, newest first, as JSON.

**Two passes, because a feed is thin.** The feed is one request per hundred
books and carries a title, a cover and a blurb — sometimes an ISBN, rarely an
author. The rest is on each book's own page. So:

1. `discover` reads feed pages and stages every product it sees, complete or
   not. Cheap, and it never fetches a product page.
2. `enrich` takes rows the gate is holding for a field the page can supply,
   reads that one page, and lays what it says over the row
   (`intake_service.apply_page_facts`). Bounded per night, and a page is read
   once.

Which is also why this needs no cursor table. Every product the feed lists is
staged, so "how far has the backlist crawl got" is just the number of rows a
store has (`backlist_pages`).

**One parser per shop, and that is not an accident to be engineered away.**
The crawl is generic; what a product row *means* is not. Speaking Tiger puts
author and ISBN in product attributes; HarperCollins puts the ISBN in the SKU
and the author only on the page; Mathrubhumi's feed has a romanized title in
capitals and its page has the title in Malayalam. Each `Store` therefore
carries two small functions, written against that shop's real payloads and
tested against trimmed copies of them.

**What a storefront does not say: who did what.** A translator and an
illustrator sit in the same list as the author, unlabelled (a third of one
HarperCollins sample). One credited name is the author. More than one goes to
`Candidate.contributors`, and the gate holds the book for `author_roles`
rather than this pipeline guessing — a translator recorded as an author is
wrong data, which is worse than a book that waits.

Politeness: one request at a time, `PAUSE_SECONDS` apart, identified by the
job's User-Agent, and only where the shop's robots.txt allows it
(niyogibooksindia.com disallows `/wp-json/`, so it is not here).

Not here yet, and why: Roli (covers are 3D mock-ups, author strings carry
ranks), Olive (fields are free text in capitals), Seagull and Juggernaut
(Shopify — the author is a URL slug or absent). Each is a `Store` away once
its author can be read reliably.

Discovery and parsing only. Nothing here creates a catalogue row.
"""

from __future__ import annotations

import asyncio
import html
import logging
import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from urllib import robotparser
from urllib.parse import urlsplit

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogIntake
from app.models.catalog_intake import STATE_INCOMPLETE
from app.services import intake_service
from app.services.intake_gate import SHOUTING_MIN_LETTERS, Candidate, is_shop_label

logger = logging.getLogger(__name__)

FEED_PATH = "/wp-json/wc/store/products"
#: The Store API's own maximum. One request, a hundred books.
PER_PAGE = 100
#: Between requests to a shop. These are small publishers' sites, not CDNs.
PAUSE_SECONDS = 1.0
#: A product page is 100–250 KB of theme. Anything far beyond is not one.
MAX_PAGE_BYTES = 1_500_000
#: Consecutive failures that mean "this shop is down or refusing us tonight".
MAX_CONSECUTIVE_FAILURES = 4
#: A blurb is a few paragraphs. A feed that returns the whole first chapter in
#: the description field should not put it in every staged row.
MAX_BLURB = 4000

FeedParser = Callable[[dict, "Store"], Candidate]
PageParser = Callable[[str], dict]


@dataclass(frozen=True)
class Store:
    """One publisher's shop: where it is, and how to read it."""

    #: The adapter's name — `catalog_intake.source`, and the catalogue
    #: provenance for books this shop is the only source of.
    source: str
    host: str
    #: The house, for a shop that sells only its own list.
    publisher: str
    from_feed: FeedParser
    #: None when the feed alone carries everything the gate asks for.
    from_page: PageParser | None = None

    @property
    def feed_url(self) -> str:
        return f"https://{self.host}{FEED_PATH}"

    def owns(self, url: str | None) -> bool:
        """A product page is only ever fetched from the shop's own host: the
        URL came out of the shop's feed, and this runs inside our network."""
        if not url:
            return False
        parts = urlsplit(url)
        bare = self.host.removeprefix("www.")
        return parts.scheme == "https" and (parts.hostname or "").removeprefix("www.") == bare


# --------------------------------------------------------------------------
# Text a shop wrote for a web page, as text for a catalogue
# --------------------------------------------------------------------------

_TAG = re.compile(r"<[^>]+>")
_BREAK = re.compile(r"(?i)<\s*(?:br\s*/?|/p|/div|/li|/h[1-6])\s*>")
_SPACES = re.compile(r"[ \t\r\f\v\u00a0]+")


def _text(fragment: str | None) -> str:
    """Markup to one line of plain text."""
    return " ".join(html.unescape(_TAG.sub(" ", fragment or "")).split())


def _blurb(fragment: str | None) -> str | None:
    """Markup to paragraphs: tags gone, paragraph breaks kept."""
    if not fragment:
        return None
    lines = html.unescape(_TAG.sub(" ", _BREAK.sub("\n", fragment))).split("\n")
    paragraphs = [cleaned for line in lines if (cleaned := _SPACES.sub(" ", line).strip())]
    text = "\n\n".join(paragraphs)
    return text[:MAX_BLURB].rstrip() or None


#: Words a title keeps small. Deliberately short — these are the ones a
#: capitals-only listing loses and a reader notices.
_SMALL_WORDS = frozenset("a an the and or but nor for of in on at to by with from as vs".split())
_ROMAN = re.compile(r"^(?=[IVX])(X{0,3})(IX|IV|V?I{0,3})$")


def _shouts(text: str, *, at_least: int = SHOUTING_MIN_LETTERS) -> bool:
    cased = [ch for ch in text if ch.isupper() or ch.islower()]
    return len(cased) >= at_least and not any(ch.islower() for ch in cased)


def _cap(word: str) -> str:
    """One word out of capitals, leaving what is meant to be capitals."""
    if "." in word or any(ch.isdigit() for ch in word) or _ROMAN.match(word):
        return word  # M.T, 2ND, III
    return "-".join(part[:1] + part[1:].lower() for part in word.split("-"))


def decase(title: str, *, always: bool = False) -> str:
    """A title a shop set in capitals, as a title.

    `always` is for a shop whose every listing is in capitals (Mathrubhumi),
    where a short one is no more an acronym than a long one. Otherwise only a
    title long enough for the gate to call it shouting is touched, so `SPQR`
    on a shop that normally writes titles properly stays `SPQR`.
    """
    if not _shouts(title, at_least=2 if always else SHOUTING_MIN_LETTERS):
        return title
    words = title.split()
    out: list[str] = []
    for index, word in enumerate(words):
        lowered = word.lower()
        opens = index == 0 or words[index - 1].endswith((":", "–", "—", "-"))
        if lowered in _SMALL_WORDS and not opens and index != len(words) - 1:
            out.append(lowered)
        else:
            out.append(_cap(word))
    return " ".join(out)


_TITLE_BREAK = re.compile(r"(\s[–—|-]\s|:\s)")


def without_tagline(title: str) -> str:
    """A title with the shop's selling line cut off the end.

    `Burnt Sugar – Shortlisted for the 2020 Booker Prize` is the book *Burnt
    Sugar* (published under the long form on the first night, 4 Oct 2026).
    Trailing parts are dropped for as long as the last one reads as a shop's
    words, or follows a pipe — no title has one. A subtitle that is just a
    subtitle (`Thriving: The Path to Mental Mastery`) is not touched, and
    neither is one that sits in front of a tagline.
    """
    parts = _TITLE_BREAK.split(title)  # text, separator, text, separator, …
    while len(parts) >= 3 and ("|" in parts[-2] or is_shop_label(parts[-1])):
        parts = parts[:-2]
    return "".join(parts).strip()


def name_case(name: str) -> str:
    """A person's name a shop set in capitals: `HAFIZ MOHAMAD N.P` →
    `Hafiz Mohamad N.P`, `KURUP K K N` → `Kurup K K N`. Initials stay as they
    are; a name already in mixed case is not touched."""
    if not _shouts(name, at_least=2):
        return name
    # Letter runs, so `R.C.KARIPPATH` is three of them: a run of one or two
    # letters is an initial and stays; anything longer is a name.
    return re.sub(
        r"[^\W\d_]+",
        lambda run: run.group(0) if len(run.group(0)) <= 2 else run.group(0).capitalize(),
        name,
    )


#: Basic Latin through Latin Extended-B, general punctuation, currency signs —
#: the same blocks `intake_openlibrary` reads as "an English record".
_LATIN_ONLY = re.compile(r"^[\u0020-\u024F\u2000-\u206F\u20A0-\u20BF]*$")


def _first_int(text: str | None) -> int | None:
    """`528 + 40-page photo insert` → 528."""
    match = re.match(r"\s*(\d{1,5})\b", text or "")
    return int(match.group(1)) if match else None


def _terms(product: dict, attribute: str) -> list[str]:
    """A WooCommerce product attribute's values, by its display name."""
    for item in product.get("attributes") or []:
        if (item.get("name") or "").strip().casefold() == attribute.casefold():
            return [t["name"].strip() for t in item.get("terms") or [] if t.get("name")]
    return []


def _images(product: dict) -> list[str]:
    return [i["src"] for i in product.get("images") or [] if i.get("src")]


def _credit(names: Sequence[str]) -> dict:
    """One credited name is the author; several are people whose roles the
    shop did not state (see the module docstring)."""
    cleaned = tuple(dict.fromkeys(n for n in (name.strip() for name in names) if n))
    if len(cleaned) == 1:
        return {"authors": cleaned}
    return {"contributors": cleaned} if cleaned else {}


def _base(product: dict, store: Store, **fields) -> Candidate:
    """The part every WooCommerce shop shares."""
    key = str(product.get("id") or "")
    blurb = _blurb(product.get("description")) or _blurb(product.get("short_description"))
    return Candidate(
        source=store.source,
        source_key=key,
        external_source=store.source,
        external_id=key,
        source_url=product.get("permalink"),
        description=blurb,
        **fields,
    )


# --------------------------------------------------------------------------
# Speaking Tiger — everything is in the feed
# --------------------------------------------------------------------------


def _speaking_tiger_feed(product: dict, store: Store) -> Candidate:
    title = without_tagline(decase(html.unescape(product.get("name") or "")))
    images = _images(product)
    return _base(
        product,
        store,
        title=title,
        isbn=next(iter(_terms(product, "ISBN")), None),
        # The imprint is what is printed on the spine: Talking Cub and Full
        # Circle are their own lists, not "Speaking Tiger".
        publisher=next(iter(_terms(product, "Imprint")), None) or store.publisher,
        page_count=_first_int(next(iter(_terms(product, "Pages")), None)),
        format=next(iter(_terms(product, "Format")), None),
        cover_url=images[0] if images else None,
        # An English-language house. A title in another script is something
        # this parser has no business labelling.
        language="English" if _LATIN_ONLY.match(title) else None,
        **_credit(_terms(product, "Author's Name")),
    )


# --------------------------------------------------------------------------
# HarperCollins India — ISBN in the SKU, author and language on the page
# --------------------------------------------------------------------------

_HC_LANGUAGES = {"eng": "English", "english": "English", "hin": "Hindi", "hindi": "Hindi"}
_HC_BYLINE = re.compile(r'<div class="hc-book-author-under-title[^"]*">(.*?)</div>', re.S)
_HC_AUTHOR = re.compile(
    r'<a[^>]+href="https://harpercollins\.co\.in/author/[^"]*"[^>]*>(.*?)</a>', re.S
)
_HC_BIO = re.compile(
    r'<h3 class="hc-author-name[^"]*">\s*<a[^>]*>(.*?)</a>\s*</h3>\s*'
    r'<div class="hc-author-bio">(.*?)</div>',
    re.S,
)
#: A biography is a paragraph. Enough to say "translator of…", not a CV.
_MAX_BIO = 1500
_HC_PAGES = re.compile(r"Pages:\s*(\d{1,5})\s*<")
_HC_LANGUAGE = re.compile(r"Language:\s*<span>\s*([^<]+?)\s*</span>")


def _harpercollins_feed(product: dict, store: Store) -> Candidate:
    # `Showtime!: A Rita Ferreira Thriller | From the author of Bhendi Bazaar`
    # — the part after the pipe is the shop's tagline, never the title.
    title = html.unescape(product.get("name") or "").split(" | ")[0].strip()
    images = _images(product)
    return _base(
        product,
        store,
        title=without_tagline(decase(title)),
        isbn=(product.get("sku") or "").strip() or None,
        publisher=store.publisher,
        cover_url=images[0] if images else None,
    )


def _harpercollins_page(page: str) -> dict:
    facts: dict = {}
    byline = _HC_BYLINE.search(page)
    if byline:
        facts.update(_credit([_text(name) for name in _HC_AUTHOR.findall(byline.group(1))]))
    # Not a field of the book: the page's "About the author" paragraphs, kept
    # because they are usually the only place a translator is called one
    # (`author_roles` reads them). Ignored by everything else.
    bios = {_text(name): _text(bio)[:_MAX_BIO] for name, bio in _HC_BIO.findall(page)}
    if bios := {name: bio for name, bio in bios.items() if name and bio}:
        facts["bios"] = bios
    if pages := _HC_PAGES.search(page):
        facts["page_count"] = int(pages.group(1))
    if language := _HC_LANGUAGE.search(page):
        raw = language.group(1).strip()
        facts["language"] = _HC_LANGUAGES.get(raw.casefold(), raw.title())
    return facts


# --------------------------------------------------------------------------
# Mathrubhumi Books — romanized capitals in the feed, Malayalam on the page
# --------------------------------------------------------------------------

_MBI_TITLE = re.compile(r'<h1[^>]*class="[^"]*product_title[^"]*"[^>]*>(.*?)</h1>', re.S)
_MBI_META = re.compile(r'<div class="product_meta">(.*?)</style>', re.S)
_MBI_WRITER = re.compile(r'<a class="sp_writer-link"[^>]*>(.*?)</a>', re.S)
_MBI_LANGUAGE = re.compile(r'class="[^"]*book_lang[^"]*"\s*>\s*Language:(.*?)</span>', re.S)
_MBI_PUBLISHER = re.compile(r'<a class="pdt_pubs-link"[^>]*>(.*?)</a>', re.S)
_MBI_PAGES = re.compile(r'class="[^"]*pdt_pages[^"]*"\s*>\s*Pages:\s*(\d{1,5})\s*</span>')
_MBI_ISBN = re.compile(r"\b(97[89]\d{10})\b")
#: The shop's own name for its own imprint, as the catalogue already spells it.
_MBI_PUBLISHERS = {"mathrubhumi": "Mathrubhumi Books"}


#: Malayalam's chillu letters, as the shop's older pages still spell them —
#: consonant + virama + zero-width joiner — and as Unicode has encoded them
#: since 5.1. Identical on the page, different to a search index: the same
#: title typed on a phone today uses the single letter.
_CHILLU = (
    ("\u0d28\u0d4d\u200d", "\u0d7b"),  # ന്‍ → ൻ
    ("\u0d30\u0d4d\u200d", "\u0d7c"),  # ര്‍ → ർ
    ("\u0d32\u0d4d\u200d", "\u0d7d"),  # ല്‍ → ൽ
    ("\u0d33\u0d4d\u200d", "\u0d7e"),  # ള്‍ → ൾ
    ("\u0d23\u0d4d\u200d", "\u0d7a"),  # ണ്‍ → ൺ
)


def _modern_chillu(text: str) -> str:
    for old, new in _CHILLU:
        text = text.replace(old, new)
    return text


def _mathrubhumi_feed(product: dict, store: Store) -> Candidate:
    images = _images(product)
    front = next((u for u in images if "front" in u.rsplit("/", 1)[-1].lower()), None)
    back = next((u for u in images if "back" in u.rsplit("/", 1)[-1].lower()), None)
    return _base(
        product,
        store,
        # Provisional: `SPINOSAURUS` for സ്പൈനോസോറസ്. The page has the real
        # one, and until it is read the gate holds the row anyway.
        title=decase(html.unescape(product.get("name") or ""), always=True),
        # Only an image the shop itself names a back cover is used as one; the
        # second image of a product is as often an inside spread.
        cover_url=front or (images[0] if images else None),
        back_cover_url=back if back != front else None,
    )


def _mathrubhumi_page(page: str) -> dict:
    facts: dict = {}
    if title := _MBI_TITLE.search(page):
        facts["title"] = _modern_chillu(decase(_text(title.group(1)), always=True))
    block = _MBI_META.search(page)
    meta = block.group(1) if block else ""
    # Labelled "Author:" by the shop, so several names here are several authors.
    writers = tuple(dict.fromkeys(name_case(_text(w)) for w in _MBI_WRITER.findall(meta)))
    if writers:
        facts["authors"] = writers
    if language := _MBI_LANGUAGE.search(meta):
        facts["language"] = _text(language.group(1)).title()
    if publisher := _MBI_PUBLISHER.search(meta):
        name = _text(publisher.group(1))
        facts["publisher"] = _MBI_PUBLISHERS.get(name.casefold(), name)
    # Anywhere in the block: the shop's template puts the number under the
    # ISBN label on most pages and under the page-count label on some.
    if isbn := _MBI_ISBN.search(_text(meta)):
        facts["isbn"] = isbn.group(1)
    if pages := _MBI_PAGES.search(meta):
        facts["page_count"] = int(pages.group(1))
    return facts


SPEAKING_TIGER = Store(
    source="speakingtiger",
    host="speakingtigerbooks.com",
    publisher="Speaking Tiger",
    from_feed=_speaking_tiger_feed,
)
HARPERCOLLINS_IN = Store(
    source="harpercollins_in",
    host="harpercollins.co.in",
    publisher="HarperCollins India",
    from_feed=_harpercollins_feed,
    from_page=_harpercollins_page,
)
MATHRUBHUMI = Store(
    source="mathrubhumi",
    host="www.mbibooks.com",
    publisher="Mathrubhumi Books",
    from_feed=_mathrubhumi_feed,
    from_page=_mathrubhumi_page,
)

STORES: tuple[Store, ...] = (HARPERCOLLINS_IN, MATHRUBHUMI, SPEAKING_TIGER)


# --------------------------------------------------------------------------
# The crawl
# --------------------------------------------------------------------------


async def read_robots(
    client: httpx.AsyncClient, store: Store
) -> robotparser.RobotFileParser | None:
    """The shop's robots.txt, parsed — or None if it could not be read.

    A shop with no robots.txt permits everything. One we cannot reach tonight
    is left alone tonight rather than assumed to agree, which is what None
    means to the caller.
    """
    rules = robotparser.RobotFileParser()
    try:
        response = await client.get(f"https://{store.host}/robots.txt")
    except httpx.HTTPError:
        return None
    if response.status_code in (404, 410):
        rules.parse([])
        return rules
    if response.status_code >= 400:
        return None
    rules.parse(response.text.splitlines())
    return rules


async def _feed_page(client: httpx.AsyncClient, store: Store, page: int) -> list[dict] | None:
    """One page of the feed, newest first. `[]` past the end, None on failure."""
    try:
        response = await client.get(
            store.feed_url,
            params={"per_page": PER_PAGE, "page": page, "orderby": "date", "order": "desc"},
        )
        response.raise_for_status()
        rows = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("intake/%s: feed page %s failed: %s", store.source, page, exc)
        return None
    return rows if isinstance(rows, list) else None


async def discover(
    client: httpx.AsyncClient,
    store: Store,
    *,
    pages: Sequence[int],
    pause: float = PAUSE_SECONDS,
) -> list[Candidate]:
    """Every product on the given feed pages, as candidates.

    Every one — a combo, a gift card and a book with no ISBN included. The gate
    decides what they are, the staging table records that it saw them, and
    that record is what tells the next night's crawl where it has got to.
    """
    found: dict[str, Candidate] = {}
    for page in pages:
        rows = await _feed_page(client, store, page)
        if pause:
            await asyncio.sleep(pause)
        if not rows:
            break  # the end of the list, or a failure: stop either way
        for product in rows:
            if not isinstance(product, dict) or not product.get("id"):
                continue
            try:
                candidate = store.from_feed(product, store)
            except Exception:  # noqa: BLE001 — one odd row must not cost the page
                logger.warning("intake/%s: could not read product %s", store.source, product["id"])
                continue
            found.setdefault(candidate.source_key, candidate)
    return list(found.values())


async def backlist_pages(db: AsyncSession, store: Store, *, count: int) -> list[int]:
    """Which feed pages tonight's backlist pass should read.

    The feed is newest-first and every product on it is staged, so the number
    of rows a store has *is* how deep the crawl has gone. It starts one page
    back from there: a book added to the shop since last night pushes
    everything down by one, and re-reading a page costs a request where
    skipping a book costs the book.
    """
    if count <= 0:
        return []
    staged = await db.scalar(
        select(func.count()).select_from(CatalogIntake).where(CatalogIntake.source == store.source)
    )
    first = max(2, (staged or 0) // PER_PAGE)
    return list(range(first, first + count))


async def _fetch_page(client: httpx.AsyncClient, url: str) -> tuple[str | None, bool]:
    """A product page's HTML, and whether a miss is final.

    `(html, _)` on success; `(None, True)` when the page is gone for good;
    `(None, False)` when it could not be read right now.
    """
    try:
        response = await client.get(url, follow_redirects=True)
    except httpx.HTTPError:
        return None, False
    if response.status_code in (404, 410):
        return None, True
    if response.status_code >= 400:
        return None, False
    body = response.text
    if len(body) > MAX_PAGE_BYTES:
        return None, True
    return body, False


async def enrich(
    db: AsyncSession,
    client: httpx.AsyncClient,
    *,
    limit: int,
    stores: Sequence[Store] = STORES,
    may_fetch: Callable[[Store, str], bool] | None = None,
    pause: float = PAUSE_SECONDS,
) -> dict[str, int]:
    """Read the product page of up to `limit` rows the gate is holding.

    Only rows that are *incomplete* — a refused row is not a book and its page
    would not change that — from a shop that has a page parser, whose page has
    not been read. New releases first, for the same reason `promote` takes
    them first. `may_fetch` is the shop's robots.txt, asked per page.
    """
    by_source = {store.source: store for store in stores if store.from_page is not None}
    if not by_source or limit <= 0:
        return {}
    fresh_first = CatalogIntake.payload.has_key(intake_service.FRESH_KEY)  # noqa: W601
    rows = (
        (
            await db.execute(
                select(CatalogIntake)
                .where(
                    CatalogIntake.source.in_(by_source),
                    CatalogIntake.state == STATE_INCOMPLETE,
                    ~CatalogIntake.payload.has_key(intake_service.PAGE_READ_KEY),  # noqa: W601
                )
                .order_by(fresh_first.desc(), CatalogIntake.first_seen_at.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )

    counts: dict[str, int] = {}
    failures: dict[str, int] = {}
    for row in rows:
        store = by_source[row.source]
        if failures.get(store.source, 0) >= MAX_CONSECUTIVE_FAILURES:
            continue  # this shop is down tonight; the others are not
        url = (row.payload or {}).get("source_url")
        if not store.owns(url) or (may_fetch is not None and not may_fetch(store, url)):
            # No page of the shop's own that we may read. Marked so it is not
            # asked about again every night.
            intake_service.apply_page_facts(row, {})
            counts["no_page"] = counts.get("no_page", 0) + 1
            continue

        page, gone = await _fetch_page(client, url)
        if pause:
            await asyncio.sleep(pause)
        if page is None and not gone:
            failures[store.source] = failures.get(store.source, 0) + 1
            counts["retry"] = counts.get("retry", 0) + 1
            continue
        failures[store.source] = 0

        try:
            facts = store.from_page(page) if page else {}
        except Exception:  # noqa: BLE001 — a page we cannot read is a page with nothing
            logger.warning("intake/%s: could not read page %s", store.source, url)
            facts = {}
        state = intake_service.apply_page_facts(row, facts)
        counts[state] = counts.get(state, 0) + 1
        await db.commit()

    await db.commit()
    return counts
