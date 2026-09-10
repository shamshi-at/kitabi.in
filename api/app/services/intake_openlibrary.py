"""Intake adapter: Indian-English books from the OpenLibrary search API.

The first source the intake spine runs on, chosen because it is the *easy*
case and so proves the machinery rather than the source. Measured 9 Sep 2026
on 60 reading-log-ranked results: 100% carried a checksum-valid ISBN, 100% an
author, 100% a publisher and 98% a cover — 98.3% complete against the gate.
OpenLibrary is already wrapped (`services/openlibrary_client`), free, and
needs no key, so nothing here adds a bill or a credential (rule 8).

**What needs care here is selection, not extraction.** A single
`language:eng subject:india` query sorted by reading-log returns Life of Pi
and Siddhartha beside The God of Small Things, and a Devanagari कामसूत्र from
a Spanish publisher. So the seeds are curated — the houses that actually
publish for Indian readers — and a script gate refuses anything not in Latin
script, because this adapter's whole claim is that it is fetching English
books.

**One edition, not a work plus an arbitrary printing.** The search is asked
for `editions.*` sub-documents, so the ISBN, publisher, cover and page count
all come off *one* edition row rather than being assembled from three. That
is the 13 Aug 2026 lesson (`editions[0]` is a representative, never an
answer): a title paired with some other printing's ISBN is a record that
looks complete and is wrong, which is worse than an incomplete one.

Discovery only. Nothing here writes to any table — it returns candidates and
`intake_service.record` decides what to do with them.
"""

from __future__ import annotations

import asyncio
import logging
import re
from collections.abc import Sequence

import httpx

from app.services.intake_gate import Candidate
from app.services.openlibrary_client import COVERS_BASE

logger = logging.getLogger(__name__)

#: The adapter's name, written into `catalog_intake.source`.
SOURCE = "openlibrary_en"
#: Catalogue provenance. Deliberately the same string `etl/03_transform.py`
#: stamped on the existing seed, so a book that seed already published is
#: recognised as a duplicate instead of created a second time.
EXTERNAL_SOURCE = "openlibrary"

SEARCH_URL = "https://openlibrary.org/search.json"
_FIELDS = ",".join(
    (
        "key",
        "title",
        "subtitle",
        "author_name",
        "first_publish_year",
        # The work-level cover, as a FALLBACK for an edition that has none.
        # Measured 11 Sep 2026: without it 26 of 50 live candidates were held
        # for a missing cover, because a specific edition row very often has
        # no `cover_i` even when the work does. The 98.3%-complete figure this
        # adapter was sized against was a WORK-level measurement; edition-level
        # covers are far sparser, and the gap is entirely this field.
        # `etl/07_language_seed.py` reached the same conclusion independently:
        # "the edition's own cover when it has one, else the work-level cover".
        "cover_i",
        "editions",
        "editions.key",
        "editions.title",
        "editions.subtitle",
        "editions.isbn",
        "editions.publisher",
        "editions.cover_i",
        "editions.language",
        "editions.number_of_pages",
    )
)

#: The houses that publish for Indian readers in English, plus two
#: subject seeds for books their publishers don't cover. Curated rather than
#: derived: "popular in India" is a judgement, and OL has no signal for it
#: beyond reading-log counts, which skew to the global head.
SEEDS: tuple[str, ...] = (
    'publisher:"Penguin Books India"',
    'publisher:"HarperCollins India"',
    'publisher:"Aleph Book Company"',
    'publisher:"Rupa Publications"',
    'publisher:"Westland"',
    'publisher:"Juggernaut Books"',
    'publisher:"Speaking Tiger"',
    'publisher:"Bloomsbury India"',
    'publisher:"Seagull Books"',
    'publisher:"Roli Books"',
    "language:eng AND subject:indic_literature",
    "language:eng AND subject:india AND subject:fiction",
)

#: Anything outside Latin + general punctuation + currency says "this is not
#: an English record" — Devanagari, Malayalam, CJK, Cyrillic, Arabic all trip
#: it. Basic Latin through Latin Extended-B, then the punctuation and currency
#: blocks a Latin title legitimately uses.
_NON_LATIN = re.compile(r"[^\x20-ɏ -⁯₠-₿]")

#: Between requests. OpenLibrary is a free service run by a non-profit and it
#: rate-limits; `etl/07_language_seed.py` settled on 4/s across all threads and
#: this is a nightly job with no deadline, so it goes slower.
PAUSE_SECONDS = 0.5
#: Results per seed per run. Deliberately small: the point is a steady trickle
#: of new books, and a seed re-queried tomorrow returns the same head anyway.
PER_SEED = 50


def _is_latin(text: str | None) -> bool:
    return bool(text) and not _NON_LATIN.search(text or "")


def _seeded_publisher(seed: str) -> str | None:
    """The house a seed named, if it named one."""
    match = re.search(r'publisher:"([^"]+)"', seed)
    return match.group(1) if match else None


def _pick_publisher(publishers: Sequence[str], seed: str) -> str | None:
    """Which of an edition's imprints to record.

    An OL edition often lists several ("Aleph", "Aleph Book Company", "Rupa
    Publications" on one row). When the seed named a house, that name is the
    most specific true answer and keeps the catalogue's spelling consistent
    with what we asked for; otherwise take the first and let
    `merge_service.canonical` sort out the spellings later.
    """
    names = [p.strip() for p in publishers if p and p.strip()]
    if not names:
        return None
    seeded = _seeded_publisher(seed)
    if seeded:
        wanted = seeded.casefold()
        for name in names:
            if name.casefold() == wanted:
                return name
        # Asked for a house, got a different one. OpenLibrary's publisher
        # search matches loosely, so `publisher:"Juggernaut Books"` returns
        # books from "Juggernaut Books Pty" — an Australian press, not the
        # Delhi one (observed live, 11 Sep 2026: it shelved an Australian YA
        # novel under an Indian-English seed). We asked for a specific house;
        # a book that does not name it is not evidence about that house.
        return None
    return names[0]


def _pick_isbn(raw: Sequence[str]) -> str | None:
    """Prefer a 13 — the gate folds a 10 up anyway, but taking the 13 when the
    edition lists both keeps the payload identical to what gets stored."""
    values = [v.strip() for v in raw if v and v.strip()]
    for value in values:
        if len(value.replace("-", "")) == 13:
            return value
    return values[0] if values else None


def _candidate(doc: dict, seed: str) -> Candidate | None:
    """One search result -> one candidate, or None if it isn't one for us."""
    work_key = doc.get("key")
    if not work_key:
        return None
    editions = ((doc.get("editions") or {}).get("docs")) or []
    if not editions:
        return None
    edition = editions[0]  # the sub-query returns the edition that matched

    # English only, stated by the edition rather than assumed from the seed.
    languages = [str(x).lower() for x in (edition.get("language") or [])]
    if languages and "eng" not in languages:
        return None

    title = edition.get("title") or doc.get("title")
    if not _is_latin(title):
        return None

    publisher = _pick_publisher(edition.get("publisher") or [], seed)
    # A publisher seed that did not find its house has learned nothing about
    # that house, so this row is not staged at all rather than staged with a
    # blank publisher. Keeping it would fill the `incomplete` queue with rows
    # no future source can resolve — the queue is supposed to be the honest
    # measure of coverage, not a log of bad matches.
    if publisher is None and _seeded_publisher(seed):
        return None

    cover_id = edition.get("cover_i") or doc.get("cover_i")
    cover_url = f"{COVERS_BASE}/b/id/{cover_id}-L.jpg" if cover_id else None

    return Candidate(
        source=SOURCE,
        # The WORK key, not the edition's: it is what the existing seed
        # stamped, and it is the level at which "we already have this book"
        # is true. The edition we chose rides along in the payload.
        source_key=str(work_key),
        external_source=EXTERNAL_SOURCE,
        external_id=str(work_key),
        title=str(title),
        subtitle=edition.get("subtitle") or doc.get("subtitle"),
        authors=tuple(str(a) for a in (doc.get("author_name") or []) if a),
        publisher=publisher,
        isbn=_pick_isbn(edition.get("isbn") or []),
        cover_url=cover_url,
        language="English",
        page_count=edition.get("number_of_pages"),
        first_publish_year=doc.get("first_publish_year"),
    )


async def discover(
    client: httpx.AsyncClient,
    *,
    seeds: Sequence[str] = SEEDS,
    per_seed: int = PER_SEED,
) -> list[Candidate]:
    """Ask each seed for its head and return the candidates, de-duplicated.

    `client` is injected so tests drive the whole adapter without the network,
    the same shape as `backfill_covers`. A seed that fails is logged and
    skipped: one bad query must not cost the whole night's intake.
    """
    found: dict[str, Candidate] = {}
    for seed in seeds:
        try:
            response = await client.get(
                SEARCH_URL,
                params={
                    "q": seed,
                    "sort": "readinglog",
                    "limit": per_seed,
                    "fields": _FIELDS,
                },
            )
            response.raise_for_status()
            docs = response.json().get("docs") or []
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("intake/openlibrary: seed %r failed: %s", seed, exc)
            continue

        for doc in docs:
            candidate = _candidate(doc, seed)
            # First seed to claim a work keeps it — the seeds are ordered
            # most-specific-first, so a publisher seed beats a subject one.
            if candidate is not None and candidate.source_key not in found:
                found[candidate.source_key] = candidate

        await asyncio.sleep(PAUSE_SECONDS)

    return list(found.values())
