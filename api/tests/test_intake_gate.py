"""The completeness gate — the rule that keeps unwanted records out.

Two properties are being pinned here, and they are the whole reason the daily
intake is allowed to run unattended:

1. **A record is complete or it is not created.** Every required field has a
   test that removes it and expects a refusal, because "we'll fill it in
   later" is what produced `etl/09_marc_cleanup.py` and `etl/10_title_restore.py`.
2. **Cleaning happens at the door.** A MARC-shaped record either comes out
   clean or is refused — it never comes out needing a second pass.

The negative cases matter as much as the positive ones. A gate that rejects
everything would pass half these tests, so the fixtures include the records
that must get through unchanged.
"""

import pytest

from app.services import marc_cleanup
from app.services.intake_gate import (
    FATAL_COVER_SCHEME,
    FATAL_NAME_JUNK,
    FATAL_OVERSIZE,
    FATAL_TITLE_JUNK,
    INVALID_ISBN,
    MISSING_AUTHORS,
    MISSING_COVER,
    MISSING_ISBN,
    MISSING_LANGUAGE,
    MISSING_PUBLISHER,
    MISSING_TITLE,
    Candidate,
    screen,
)

GOOD = dict(
    source="openlibrary_en",
    source_key="/works/OL1W",
    title="The God of Small Things",
    authors=("Arundhati Roy",),
    publisher="HarperCollins India",
    isbn="9780060977498",
    cover_url="https://covers.openlibrary.org/b/id/1-L.jpg",
    language="English",
)


def candidate(**over) -> Candidate:
    return Candidate(**{**GOOD, **over})


# --------------------------------------------------------------------------
# a complete record passes, untouched
# --------------------------------------------------------------------------


def test_a_complete_record_passes_and_is_not_altered():
    result = screen(candidate())
    assert result.ok
    assert result.missing == ()
    assert result.fatal == ()
    assert result.candidate.title == GOOD["title"]
    assert result.candidate.authors == GOOD["authors"]
    assert result.candidate.publisher == GOOD["publisher"]


@pytest.mark.parametrize(
    ("field", "reason"),
    [
        ("title", MISSING_TITLE),
        ("authors", MISSING_AUTHORS),
        ("publisher", MISSING_PUBLISHER),
        ("isbn", MISSING_ISBN),
        ("cover_url", MISSING_COVER),
        ("language", MISSING_LANGUAGE),
    ],
)
def test_every_required_field_is_actually_required(field, reason):
    """One test per field, because a gate is only as strong as its weakest
    predicate and a missing `elif` is invisible by inspection."""
    blank = () if field == "authors" else None
    result = screen(candidate(**{field: blank}))
    assert not result.ok
    assert reason in result.missing


def test_an_incomplete_record_is_waiting_not_refused():
    """The distinction the queue is built on: a book with no ISBN yet is a gap
    another source can fill, not a record we refuse forever."""
    result = screen(candidate(isbn=None))
    assert not result.ok
    assert not result.rejected
    assert result.fatal == ()


# --------------------------------------------------------------------------
# ISBN: checksum AND prefix
# --------------------------------------------------------------------------


def test_a_valid_isbn10_is_folded_up_to_the_thirteen_we_store():
    assert screen(candidate(isbn="0060977493")).candidate.isbn == "9780060977498"


def test_a_hyphenated_isbn_is_accepted():
    assert screen(candidate(isbn="978-0-06-097749-8")).candidate.isbn == "9780060977498"


def test_a_979_isbn_is_accepted():
    """979 has no ISBN-10 equivalent, so a naive fold-to-10 rejects it."""
    result = screen(candidate(isbn="9791234567896"))
    assert result.ok
    assert result.candidate.isbn == "9791234567896"


def test_a_checksum_valid_number_with_no_bookland_prefix_is_refused():
    """`9189376880780` is off a real publisher's product page (mbibooks.com,
    9 Sep 2026). It passes the mod-10 check by coincidence and is not an ISBN
    — no `918` prefix exists. One wrong number in ten passes a mod-10 check,
    so the checksum alone is not a gate.
    """
    result = screen(candidate(isbn="9189376880780"))
    assert not result.ok
    assert INVALID_ISBN in result.missing
    assert result.candidate.isbn is None


def test_a_mistyped_isbn_is_reported_separately_from_an_absent_one():
    """So the queue can tell "this source has no number" from "this source has
    a bad one" — only the second is worth reporting upstream."""
    assert INVALID_ISBN in screen(candidate(isbn="9780060977499")).missing
    assert MISSING_ISBN in screen(candidate(isbn=None)).missing


def test_a_bad_isbn_is_dropped_not_stored():
    """A number that isn't an ISBN must not sit in the payload looking like
    one — the next reader of that row would take it at face value."""
    assert screen(candidate(isbn="not-a-number")).candidate.isbn is None


# --------------------------------------------------------------------------
# cleaning at the door — the "no more adjustment records" guarantee
# --------------------------------------------------------------------------


def test_marc_punctuation_is_cleaned_before_the_record_is_created():
    result = screen(candidate(title="Gandhiji.", publisher="DC Books."))
    assert result.ok
    assert result.candidate.title == "Gandhiji"
    assert result.candidate.publisher == "DC Books"


def test_an_inverted_author_name_is_un_inverted():
    result = screen(candidate(authors=("Basheer, Vaikom Muhammad",)))
    assert result.ok
    assert result.candidate.authors == ("Vaikom Muhammad Basheer",)


def test_a_dangling_marc_separator_is_stripped():
    assert screen(candidate(title="Sagar pataal ma safar =")).candidate.title == (
        "Sagar pataal ma safar"
    )


def test_a_spaced_isbd_colon_becomes_a_subtitle():
    result = screen(candidate(title="Kayar : a novel"))
    assert result.candidate.title == "Kayar"
    assert result.candidate.subtitle == "a novel"


def test_what_the_gate_lets_through_needs_no_second_pass():
    """The acceptance property for the whole plan (docs/catalog-intake-plan.md
    §5, P6): re-running the cleanup rules over a promoted record must find
    nothing to do. Asserted directly rather than waited for in production.
    """
    dirty = candidate(
        title='"Mukajjiya kanasugaḷu" /',
        authors=("Basheer, Vaikom Muhammad",),
        publisher="Mathrubhumi Books.",
    )
    cleaned = screen(dirty).candidate
    again = marc_cleanup.clean_work(cleaned.title, cleaned.subtitle, tuple(cleaned.authors))
    assert again.rules == [], f"still needs {again.rules}"
    for name in cleaned.authors:
        assert marc_cleanup.clean_name(name, uninvert=True).rules == []


# --------------------------------------------------------------------------
# fatal — records that must never become books
# --------------------------------------------------------------------------


def test_a_supplied_heading_is_refused_not_repaired():
    """`[South Asia pamphlet collection.` is MARC's mark for a heading a
    cataloguer invented because the item had no title page — which here means
    the row is not a book. Un-bracketing it would make it look more legitimate
    without making it more true (`services/marc_cleanup`'s own rule).
    """
    result = screen(candidate(title="[South Asia pamphlet collection."))
    assert result.rejected
    assert FATAL_TITLE_JUNK in result.fatal


def test_a_truncated_import_is_refused():
    result = screen(candidate(title="Research Department, D.A.V. (College"))
    assert result.rejected


def test_a_refused_record_reports_no_missing_fields():
    """It is not waiting for anything — saying "waiting on: isbn" about a row
    we will never accept would put it in the wrong queue."""
    result = screen(candidate(title="[South Asia pamphlet collection.", isbn=None))
    assert result.rejected
    assert result.missing == ()


def test_a_name_with_two_commas_is_refused_rather_than_guessed():
    result = screen(candidate(authors=("Smith, John, Jr., editor",)))
    assert result.rejected
    assert FATAL_NAME_JUNK in result.fatal


def test_an_http_cover_is_refused_not_treated_as_absent():
    """The app and the edge proxy both refuse non-https, so an http cover is a
    blank box, not a picture — and no other source will supply this one."""
    result = screen(candidate(cover_url="http://covers.example.com/1.jpg"))
    assert result.rejected
    assert FATAL_COVER_SCHEME in result.fatal


def test_a_pasted_description_in_the_title_field_is_refused():
    result = screen(candidate(title="A " + "very long " * 60))
    assert result.rejected
    assert FATAL_OVERSIZE in result.fatal


# --------------------------------------------------------------------------
# the records that must come through UNCHANGED
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "title",
    [
        "4:50 from Paddington",  # a departure time, not an ISBD subtitle
        "Death: Before, During & After",  # unspaced colon, a real title
        "Who Moved My Cheese?",
        "Ph.D",  # a load-bearing terminal period
    ],
)
def test_a_real_title_is_not_mangled(title):
    """Half the value of `marc_cleanup` is what it leaves alone; a gate that
    quietly rewrote these would be worse than no gate."""
    result = screen(candidate(title=title))
    assert result.ok
    assert result.candidate.title == title


def test_a_native_script_title_passes():
    """The gate is script-agnostic — refusing non-Latin here would rule out the
    wedge language. Script selection belongs to the adapter that fetched it."""
    result = screen(candidate(title="ചെമ്മീൻ", authors=("തകഴി ശിവശങ്കരപ്പിള്ള",)))
    assert result.ok
    assert result.candidate.title == "ചെമ്മീൻ"


def test_duplicate_authors_are_collapsed_but_order_is_kept():
    result = screen(candidate(authors=("A Roy", "B Sen", "A Roy")))
    assert result.candidate.authors == ("A Roy", "B Sen")


def test_an_absurd_page_count_is_dropped_without_failing_the_record():
    """A parse error in one optional field must not cost a good book."""
    result = screen(candidate(page_count=999_999))
    assert result.ok
    assert result.candidate.page_count is None


# --------------------------------------------------------------------------
# the payload round-trip — what re-screening depends on
# --------------------------------------------------------------------------


def test_a_candidate_survives_the_round_trip_through_jsonb():
    """`rescreen_incomplete` replays the stored payload, so anything lost here
    is silently lost from every held row."""
    original = candidate(subtitle="a novel", page_count=340, external_source="openlibrary")
    restored = Candidate.from_payload(original.to_payload())
    assert restored == original
    assert restored.provenance == ("openlibrary", "/works/OL1W")


def test_provenance_falls_back_to_the_adapters_own_identity():
    """A source with no upstream catalogue of its own still needs to be
    recognisable on a second run."""
    assert candidate(external_source=None, external_id=None).provenance == (
        "openlibrary_en",
        "/works/OL1W",
    )


def test_a_trailing_comma_is_stripped_from_a_publisher_name():
    """`Juggernaut Books Pty,` is what OpenLibrary actually returned on
    11 Sep 2026. A comma *inside* a publisher name is often load-bearing (a
    department, an address) and `marc_cleanup` rightly leaves those alone —
    but a comma at the very end never is, and a reader would see it."""
    assert screen(candidate(publisher="Juggernaut Books Pty,")).candidate.publisher == (
        "Juggernaut Books Pty"
    )


def test_a_comma_inside_a_publisher_name_is_left_alone():
    """The other half — 55 of 1,021 seeded publisher names carry a comma and
    not one of them is junk."""
    name = "Ramakrishna Vedanta Math, Publication Dept."
    assert screen(candidate(publisher=name)).candidate.publisher == name
