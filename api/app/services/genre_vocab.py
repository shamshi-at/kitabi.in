"""The closed genre vocabulary, and the careful reader for LLM classification.

Genres are Layer-1 catalog data with indexed public hub pages riding on them
(`/genre/<slug>`), so the vocabulary is CLOSED: a classifier — human or model —
picks from this list or says nothing. Free-text genres would recreate the
near-duplicate mess the `normalize_form` vocabulary exists to prevent, except
on pages Google reads (docs/tasks.md W5; CLAUDE.md rule 18 keeps personal tags
out of here entirely).

Deliberately orthogonal to `WORK_FORMS`: "Poetry", "Biography", "Memoir",
"Essays", "Travelogue", "Children's" are *forms* (the Type facet), so they are
not genres too — a work is `form=Biography, genres=[History]`, never
`genres=[Biography]`. The one rule that keeps both facets meaningful.

Names are reader-facing (they become hub headings) and must slugify uniquely —
`test_genre_vocab.py` pins that, because two names colliding on one slug means
one hub silently shadows the other.
"""

from __future__ import annotations

import json
import re
from typing import Any

from app.schemas.catalog import WORK_FORMS, normalize_form

# ~40 max by design (docs/tasks.md). Broad on purpose: 1,405 works across 14
# languages need hubs with mass, not a taxonomy — "Psychological literary
# horror" splits a 12-book shelf three ways. Fiction first, then nonfiction.
GENRES: tuple[str, ...] = (
    # Fiction
    "Literary fiction",
    "Historical fiction",
    "Social fiction",
    "Political fiction",
    "Romance",
    "Crime & mystery",
    "Thriller & suspense",
    "Science fiction",
    "Fantasy",
    "Horror",
    "Mythological fiction",
    "Satire & humour",
    "Family saga",
    "Coming of age",
    "War fiction",
    "Adventure",
    "Folklore & fairy tales",
    "Young adult",
    # Nonfiction
    "History",
    "Politics & society",
    "Philosophy",
    "Religion & spirituality",
    "Science & nature",
    "Self-help",
    "Business & economics",
    "Literary criticism",
    "Language & linguistics",
    "Art & cinema",
    "Health & wellness",
    "Food & cooking",
    "Sports",
    "True crime",
    "Education & reference",
)

_BY_FOLD = {g.casefold(): g for g in GENRES}

CONFIDENCES = ("high", "medium", "low", "unknown")


def normalize_genre(value: str | None) -> str | None:
    """The vocabulary spelling for a candidate, or None when it isn't in the
    vocabulary at all — unlike `normalize_form`, an unknown value is REJECTED,
    never kept: this list is closed."""
    if not value:
        return None
    return _BY_FOLD.get(" ".join(value.split()).casefold())


def parse_classification(raw: str, expected_ids: set[str]) -> tuple[list[dict], list[str]]:
    """Read one model reply into per-work rows, eagerly and defensively.

    Element-by-element on purpose (CLAUDE.md, 21 Jul 2026): a shape surprise
    must fail HERE, at the boundary, as a skipped row in the second return —
    never later inside an apply loop. Never raises on content; the caller
    treats `problems` as rows to re-ask or leave unclassified.

    Returns (rows, problems). Each row:
        {"id": str, "genres": [vocab names, ≤3], "form": WORK_FORMS name|None,
         "confidence": one of CONFIDENCES}
    Rules enforced: ids must be in `expected_ids` (a model inventing or
    repeating an id is a problem, not a row); genres outside the vocabulary
    are dropped (and noted) rather than imported; an empty genre list forces
    confidence "unknown".
    """
    rows: list[dict] = []
    problems: list[str] = []

    match = re.search(r"\[.*\]", raw, re.S)
    if not match:
        return [], [f"no JSON array in reply ({raw[:80]!r}…)"]
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError as exc:
        return [], [f"unparseable JSON: {exc}"]
    if not isinstance(data, list):
        return [], ["reply JSON is not a list"]

    seen: set[str] = set()
    for item in data:
        if not isinstance(item, dict):
            problems.append(f"non-object element: {item!r}")
            continue
        work_id = str(item.get("id", ""))
        if work_id not in expected_ids:
            problems.append(f"unexpected id {work_id!r}")
            continue
        if work_id in seen:
            problems.append(f"duplicate id {work_id!r}")
            continue
        seen.add(work_id)

        raw_genres = item.get("genres")
        genres: list[str] = []
        if isinstance(raw_genres, list):
            for g in raw_genres[:3]:
                known = normalize_genre(g if isinstance(g, str) else None)
                if known is None:
                    problems.append(f"{work_id}: dropped non-vocabulary genre {g!r}")
                elif known not in genres:
                    genres.append(known)

        form_raw = item.get("form")
        form = normalize_form(form_raw) if isinstance(form_raw, str) else None
        if form is not None and form not in WORK_FORMS:
            # normalize_form keeps custom spellings; the classifier doesn't
            # get that latitude — it was told the list.
            problems.append(f"{work_id}: dropped non-vocabulary form {form_raw!r}")
            form = None

        confidence = item.get("confidence")
        if confidence not in CONFIDENCES:
            confidence = "low"
        if not genres and form is None:
            confidence = "unknown"

        rows.append({"id": work_id, "genres": genres, "form": form, "confidence": confidence})

    return rows, problems


def classification_prompt(works: list[dict[str, Any]]) -> str:
    """One batch's user message. `works` rows carry id/title/authors/language/
    year/form/description — description already truncated by the caller."""
    lines = [
        "Classify each of these books from a South Asian personal-library catalogue.",
        "",
        "GENRES — pick 1-3 from EXACTLY this list, primary first (or [] if you",
        "genuinely cannot tell — never guess a plausible-sounding genre):",
        "; ".join(GENRES),
        "",
        "FORM — one of EXACTLY this list, or null if unclear:",
        "; ".join(WORK_FORMS),
        "",
        "CONFIDENCE — 'high' only when you recognise the specific work or author;",
        "'medium' when the description/title makes it clear; 'low' when inferring",
        "from thin evidence; 'unknown' when classifying would be a guess.",
        "",
        "Many titles are romanized from Indic scripts (ITRANS-style) — recognise",
        "works through the romanization where you can. A well-known author's",
        "typical genre is medium evidence, not high, unless you know the work.",
        "",
        "Reply with ONLY a JSON array, one object per book, same ids, no prose:",
        '[{"id": "...", "genres": ["..."], "form": "..." , "confidence": "high"}]',
        "",
        "BOOKS:",
    ]
    for w in works:
        bits = [f"id={w['id']}", f"title={w['title']!r}"]
        if w.get("authors"):
            bits.append(f"authors={w['authors']!r}")
        if w.get("language"):
            bits.append(f"language={w['language']}")
        if w.get("year"):
            bits.append(f"year={w['year']}")
        if w.get("form"):
            bits.append(f"form={w['form']}")
        if w.get("description"):
            bits.append(f"description={w['description']!r}")
        lines.append("- " + " | ".join(bits))
    return "\n".join(lines)
