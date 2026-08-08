"""The closed genre vocabulary and its LLM-reply reader.

These genres become indexed public hub pages (`/genre/<slug>`), so the
invariants pinned here are load-bearing for the site, not just the classifier:
slug uniqueness (two names on one slug = one hub silently shadowing another),
form-orthogonality (a "Poetry" genre would split the Type facet against the
genre facet), and the reader's refusal to import anything outside the list.
"""

from app.schemas.catalog import WORK_FORMS
from app.services.genre_vocab import (
    GENRES,
    classification_prompt,
    normalize_genre,
    parse_classification,
)
from app.services.slug_service import slugify


def test_vocabulary_is_closed_sized_and_slug_unique():
    assert len(GENRES) <= 40, "the vocabulary is ~40 by design (docs/tasks.md W5)"
    assert len(set(GENRES)) == len(GENRES)
    slugs = [slugify(g) for g in GENRES]
    assert None not in slugs, "every genre must produce a hub slug"
    assert len(set(slugs)) == len(slugs), "two genres colliding on one slug shadows a hub"


def test_genres_are_orthogonal_to_forms():
    """form=Biography + genres=[History], never genres=[Biography] — one facet
    per concept or both facets stop meaning anything."""
    overlap = {g.casefold() for g in GENRES} & {f.casefold() for f in WORK_FORMS}
    assert not overlap, f"genres duplicating forms: {overlap}"


def test_normalize_genre_is_case_insensitive_and_closed():
    assert normalize_genre("historical FICTION") == "Historical fiction"
    assert normalize_genre("  crime  &  mystery ") == "Crime & mystery"
    assert normalize_genre("Chick lit") is None, "outside the vocabulary is rejected, not kept"
    assert normalize_genre(None) is None
    assert normalize_genre("") is None


def test_parse_takes_only_expected_ids_and_vocabulary_values():
    raw = """Here you go:
    [
      {"id": "a", "genres": ["Romance", "Bodice ripper", "Romance"], "form": "novel",
       "confidence": "high"},
      {"id": "a", "genres": ["Horror"], "confidence": "high"},
      {"id": "z", "genres": ["Horror"], "confidence": "high"},
      {"id": "b", "genres": [], "form": null, "confidence": "high"},
      {"id": "c", "genres": ["Fantasy"], "form": "Scroll", "confidence": "definitely"},
      "not an object"
    ]"""
    rows, problems = parse_classification(raw, expected_ids={"a", "b", "c"})

    by_id = {r["id"]: r for r in rows}
    # a: non-vocab genre dropped, duplicate genre deduped, form case-folded.
    assert by_id["a"]["genres"] == ["Romance"]
    assert by_id["a"]["form"] == "Novel"
    # b: nothing classified — confidence forced to unknown regardless of claim.
    assert by_id["b"]["confidence"] == "unknown"
    # c: unknown form dropped, invalid confidence degrades to low.
    assert by_id["c"] == {"id": "c", "genres": ["Fantasy"], "form": None, "confidence": "low"}
    # The duplicate "a", the invented "z", and the junk element are problems,
    # not rows.
    assert len(rows) == 3
    assert any("duplicate id" in p for p in problems)
    assert any("unexpected id" in p for p in problems)
    assert any("Bodice ripper" in p for p in problems)
    assert any("Scroll" in p for p in problems)


def test_parse_survives_garbage_replies():
    assert parse_classification("no json here", {"a"}) == (
        [],
        ["no JSON array in reply " "('no json here'…)"],
    )
    rows, problems = parse_classification("[{broken", {"a"})
    assert rows == [] and problems
    rows, problems = parse_classification('["just", "strings"]', {"a"})
    assert rows == [] and len(problems) == 2


def test_parse_caps_genres_at_three():
    raw = '[{"id": "a", "genres": ["Romance", "Horror", "Fantasy", "Adventure"], '
    raw += '"confidence": "high"}]'
    rows, _ = parse_classification(raw, {"a"})
    assert rows[0]["genres"] == ["Romance", "Horror", "Fantasy"]


def test_prompt_carries_every_work_and_both_vocabularies():
    works = [
        {
            "id": "w1",
            "title": "ചെമ്മീൻ",
            "authors": "Thakazhi",
            "language": "Malayalam",
            "year": 1956,
            "form": None,
            "description": "Fisherfolk of Kerala",
        },
        {
            "id": "w2",
            "title": "Plain",
            "authors": "",
            "language": None,
            "year": None,
            "form": None,
            "description": "",
        },
    ]
    prompt = classification_prompt(works)
    assert "w1" in prompt and "w2" in prompt and "ചെമ്മീൻ" in prompt
    for genre in GENRES:
        assert genre in prompt
    for form in WORK_FORMS:
        assert form in prompt
    assert "never guess" in prompt
