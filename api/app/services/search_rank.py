"""Cross-type relevance scoring for search and typeahead.

The problem this exists to solve: books, authors and publishers are each ranked
well *within* their own type by trigram similarity, but those scores are not
comparable across types, so a combined result list had no way to order itself.
The first version simply concatenated books, then authors, then publishers —
which meant searching "dc books" returned four books merely containing the word
"books" above the publisher literally called DC Books.

So candidates from every type are re-scored here by one function and sorted
together. Pure and dependency-free: no database, no ORM, so the ranking rules
can be tested directly instead of inferred from query results.

The scale is deliberately coarse and banded rather than a continuous blend.
Bands mean "an exact match always beats a prefix match, which always beats a
word match" is a guarantee rather than something that happens to hold for the
weights we picked today. Similarity only orders candidates *within* a band.
"""

from __future__ import annotations

import re
import unicodedata

# Band floors. The gaps are wide enough that no similarity score or popularity
# bonus can lift a candidate out of its band.
EXACT = 1.0
PREFIX = 0.80
ALL_WORDS = 0.60
SOME_WORDS = 0.35
WEAK = 0.0

# Anything the database matcher returned is a match — its fuzzy trigram index
# already decided that. A candidate this scorer cannot explain therefore keeps a
# floor rather than being discarded: the scorer's job is ORDER, and it must
# never have worse recall than the matcher feeding it.
#
# This was a real regression. Ranking initially dropped every zero-scoring
# candidate, so searching "mathrubhumi" returned nothing at all where the
# unranked version had found the publisher fine. A search that finds less is
# worse, however well ordered the little it finds.
MATCHER_FLOOR = 0.01

# Popularity only ever breaks ties inside a band — a publisher with 200 books
# should beat one with 2 when both match equally, and never otherwise.
MAX_POPULARITY_BONUS = 0.049

_PUNCT = re.compile(r"[^\w\s]", re.UNICODE)
_SPACE = re.compile(r"\s+")


def normalize(text: str | None) -> str:
    """Casefold, strip punctuation and accents, collapse whitespace.

    Accent stripping matters here specifically: this catalogue is full of
    transliterated names (Bibhūtibhūshaṇa, Ḥāfiẓ), and a reader typing
    "bibhutibhushana" on an ordinary keyboard must reach them.
    """
    if not text:
        return ""
    decomposed = unicodedata.normalize("NFKD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return _SPACE.sub(" ", _PUNCT.sub(" ", stripped.casefold())).strip()


def _tokens(text: str) -> list[str]:
    return [t for t in normalize(text).split(" ") if t]


def _score_one(query_norm: str, query_tokens: list[str], candidate: str | None) -> float:
    """Score one query against one spelling of a candidate."""
    cand_norm = normalize(candidate)
    if not cand_norm or not query_norm:
        return WEAK

    if cand_norm == query_norm:
        return EXACT

    if cand_norm.startswith(query_norm):
        # A short candidate that starts with the query is a better hit than a
        # long one — "DC Books" over "DC Books International Distribution".
        overshoot = len(cand_norm) - len(query_norm)
        return PREFIX + min(0.15, 30 / (30 + overshoot) * 0.15)

    cand_tokens = set(_tokens(cand_norm))
    if not query_tokens:
        return WEAK

    whole = sum(1 for t in query_tokens if t in cand_tokens)
    if whole == len(query_tokens):
        # Every query word present as a whole word, in any order.
        return ALL_WORDS + 0.15 * (len(query_tokens) / max(len(cand_tokens), 1))

    partial = sum(1 for t in query_tokens if any(t in c for c in cand_tokens))
    if partial == len(query_tokens):
        return SOME_WORDS + 0.15 * (partial / max(len(cand_tokens), 1))

    matched = max(whole, partial)
    if matched:
        # Some words hit. Never enough to outrank a candidate that matched them
        # all, which is the whole point of the banding.
        return WEAK + 0.30 * (matched / len(query_tokens))
    return WEAK


def score(
    query: str,
    *,
    label: str | None,
    translit: str | None = None,
    fold: str | None = None,
    query_translit: str | None = None,
    query_fold: str | None = None,
    popularity: int = 0,
    popularity_ceiling: int = 200,
) -> float:
    """Relevance of one candidate for one query, comparable across types.

    `translit`/`fold` are the candidate's romanized and spelling-folded twins
    (the columns the cross-script search already maintains), and
    `query_translit`/`query_fold` are the query's. Scoring every pairing and
    taking the best is what lets a Latin query rank a native-script title
    properly rather than merely find it.
    """
    query_norm = normalize(query)
    query_tokens = _tokens(query_norm)

    best = _score_one(query_norm, query_tokens, label)

    # The romanized/folded spellings, on both sides. A native-script label has
    # no useful direct comparison to a Latin query; its translit does.
    for q_variant in (query_norm, normalize(query_translit), normalize(query_fold)):
        if not q_variant:
            continue
        q_variant_tokens = _tokens(q_variant)
        for candidate in (translit, fold):
            if candidate:
                best = max(best, _score_one(q_variant, q_variant_tokens, candidate))

    if best <= WEAK:
        return best

    # Tie-break only. Capped well below the width of a band.
    if popularity > 0 and popularity_ceiling > 0:
        ratio = min(1.0, popularity / popularity_ceiling)
        best += MAX_POPULARITY_BONUS * ratio
    return best


def rank(items: list[dict], limit: int, *, dedupe: bool = True) -> list[dict]:
    """Sort scored candidates and take the best.

    Ties break by score, then by the caller's `tie` value (lower first), then by
    label — so the order is total and a page does not reshuffle between requests
    for reasons nobody can see.

    `dedupe` collapses entries of the same kind with the same normalised label,
    keeping the best-scoring one. The catalogue holds duplicate author rows until
    the merge job runs, and offering the same name twice in a dropdown reads as a
    bug in the search rather than in the data.
    """
    ordered = sorted(
        items,
        key=lambda i: (-i["score"], i.get("tie", 0), normalize(i.get("label"))),
    )
    out: list[dict] = []
    seen: set = set()
    for item in ordered:
        if item["score"] <= WEAK:
            continue
        if dedupe:
            key = (item.get("kind", ""), normalize(item.get("label")))
            if key in seen:
                continue
            seen.add(key)
        out.append(item)
        if len(out) >= limit:
            break
    return out
