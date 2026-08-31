"""The title-restoration parser — above all, the guards that reject an answer.

The model's job here is recall, and recall fails quietly: a plausible wrong
title looks exactly like a right one to a reviewer who does not read the
script. So the parser's value is not in what it accepts but in what it refuses
— a "native" answer that is not in that language's script, an "english" answer
carrying Indic characters, an id nobody asked about. Those are the cases below.
"""

from app.services import title_restore as tr

GUJARATI = {"w1": "Gujarati"}


def _one(raw, expected=None):
    rows, problems = tr.parse_restoration(raw, expected or GUJARATI)
    return rows[0] if rows else None, problems


# --------------------------------------------------------------------------
# what it accepts
# --------------------------------------------------------------------------


def test_accepts_a_native_title_in_the_right_script():
    row, problems = _one(
        '[{"id":"w1","kind":"native","title":"આઝાદી અડધી રાતે",' '"confidence":"high"}]'
    )
    assert row == {"id": "w1", "kind": "native", "title": "આઝાદી અડધી રાતે", "confidence": "high"}
    assert problems == []


def test_accepts_the_english_title_of_a_double_transliterated_work():
    """`3 misṭeka ôpha māya lāipha` is Chetan Bhagat in English, printed in
    Gujarati letters and romanized back out. `ôpha` is "of"."""
    row, problems = _one(
        '[{"id":"w1","kind":"english",' '"title":"The 3 Mistakes of My Life","confidence":"high"}]'
    )
    assert row["kind"] == "english"
    assert row["title"] == "The 3 Mistakes of My Life"
    assert problems == []


def test_unchanged_and_unknown_carry_no_title():
    for kind in ("unchanged", "unknown"):
        row, _ = _one(f'[{{"id":"w1","kind":"{kind}","title":"something",' '"confidence":"high"}]')
        assert row["title"] is None


# --------------------------------------------------------------------------
# the guards — what it refuses
# --------------------------------------------------------------------------


def test_rejects_a_native_title_that_is_still_romanized():
    """The exact thing we are removing. A model that answers with the
    romanization has not converted anything."""
    row, problems = _one(
        '[{"id":"w1","kind":"native","title":"Ardhi rate azadi",' '"confidence":"high"}]'
    )
    assert row["kind"] == "unknown"
    assert row["title"] is None
    assert any("not in Gujarati script" in p for p in problems)


def test_rejects_a_native_title_in_the_wrong_script():
    """Devanagari returned for a Gujarati work — precisely the failure that
    sank the mechanical sanscript conversion (ऎ/ऒ/ॆ bleeding into Gujarati),
    and one a reviewer who doesn't read either script cannot see."""
    row, problems = _one(
        '[{"id":"w1","kind":"native","title":"आझादी अडधी राते",' '"confidence":"high"}]'
    )
    assert row["kind"] == "unknown"
    assert any("not in Gujarati script" in p for p in problems)


def test_rejects_an_english_title_carrying_indic_script():
    row, problems = _one(
        '[{"id":"w1","kind":"english","title":"The ૩ Mistakes",' '"confidence":"high"}]'
    )
    assert row["kind"] == "unknown"
    assert any("non-Latin" in p for p in problems)


def test_rejects_an_id_nobody_asked_about():
    rows, problems = tr.parse_restoration(
        '[{"id":"nope","kind":"english","title":"X","confidence":"high"}]', GUJARATI
    )
    assert rows == []
    assert any("unexpected id" in p for p in problems)


def test_rejects_a_duplicate_id():
    rows, problems = tr.parse_restoration(
        '[{"id":"w1","kind":"unchanged","confidence":"high"},'
        '{"id":"w1","kind":"english","title":"X","confidence":"high"}]',
        GUJARATI,
    )
    assert len(rows) == 1
    assert any("duplicate id" in p for p in problems)


def test_a_kind_with_no_title_becomes_unknown():
    row, problems = _one('[{"id":"w1","kind":"native","confidence":"high"}]')
    assert row["kind"] == "unknown"
    assert any("no title" in p for p in problems)


def test_notes_rows_the_model_silently_dropped():
    _, problems = tr.parse_restoration(
        '[{"id":"w1","kind":"unchanged","confidence":"high"}]',
        {"w1": "Gujarati", "w2": "Tamil"},
    )
    assert any("absent from the reply" in p for p in problems)


def test_survives_a_reply_that_is_not_json():
    rows, problems = tr.parse_restoration("I'm afraid I can't help with that.", GUJARATI)
    assert rows == []
    assert problems and "no JSON array" in problems[0]


def test_an_unrecognised_confidence_degrades_rather_than_raising():
    row, _ = _one('[{"id":"w1","kind":"english","title":"X","confidence":"certain"}]')
    assert row["confidence"] == "low"


# --------------------------------------------------------------------------
# script membership
# --------------------------------------------------------------------------


def test_in_script_knows_the_scripts_apart():
    assert tr.in_script("આઝાદી", "Gujarati")
    assert not tr.in_script("आझादी", "Gujarati")  # Devanagari
    assert tr.in_script("ചെമ്മീൻ", "Malayalam")
    assert not tr.in_script("Chemmeen", "Malayalam")
    # Hindi, Marathi and Sanskrit share Devanagari on purpose — the check is
    # "right script at all", not "which of two languages that share one".
    assert tr.in_script("आझादी", "Marathi") and tr.in_script("आझादी", "Hindi")
    assert not tr.in_script("anything", "Klingon")


# --------------------------------------------------------------------------
# self-consistency
# --------------------------------------------------------------------------


def _run(*pairs):
    """One run's parsed rows, from (id, kind, title, confidence) tuples."""
    return [{"id": i, "kind": k, "title": t, "confidence": c} for i, k, t, c in pairs]


def test_the_majority_answer_wins():
    """The Akhet case, exactly. Two runs said આખેટ, one said અખેત, and the
    single-vote pipeline shipped the odd one out to production at `high`."""
    rows = tr.tally_votes(
        [
            _run(("w1", "native", "આખેટ", "high")),
            _run(("w1", "native", "આખેટ", "high")),
            _run(("w1", "native", "અખેત", "high")),
        ],
        {"w1": "Gujarati"},
    )
    assert rows[0]["title"] == "આખેટ"
    assert rows[0]["votes"] == 2 and rows[0]["runs"] == 3


def test_three_different_answers_is_not_an_answer():
    rows = tr.tally_votes(
        [
            _run(("w1", "native", "અ", "high")),
            _run(("w1", "native", "આ", "high")),
            _run(("w1", "native", "ઇ", "high")),
        ],
        {"w1": "Gujarati"},
    )
    assert rows[0]["kind"] == "unknown"
    assert rows[0]["title"] is None
    assert rows[0]["votes"] == 1


def test_a_tie_is_not_agreement():
    """Two runs, two answers. `most_common` would hand one of them the win."""
    rows = tr.tally_votes(
        [_run(("w1", "native", "અ", "high")), _run(("w1", "native", "આ", "high"))],
        {"w1": "Gujarati"},
    )
    assert rows[0]["kind"] == "unknown"


def test_runs_must_agree_on_the_kind_too():
    """Same book, one run calls it native and one english — that is a
    disagreement about what the title IS, not a spelling difference."""
    rows = tr.tally_votes(
        [
            _run(("w1", "native", "આઈ એમ ઓકે", "high")),
            _run(("w1", "english", "I'm OK, You're OK", "high")),
            _run(("w1", "english", "I'm OK, You're OK", "high")),
        ],
        {"w1": "Gujarati"},
    )
    assert rows[0]["kind"] == "english"
    assert rows[0]["votes"] == 2


def test_unicode_normalisation_is_not_a_disagreement():
    import unicodedata

    composed = "आधी रात की संतानें"
    rows = tr.tally_votes(
        [
            _run(("w1", "native", composed, "high")),
            _run(("w1", "native", unicodedata.normalize("NFD", composed), "high")),
        ],
        {"w1": "Hindi"},
    )
    assert rows[0]["votes"] == 2


def test_reports_the_least_confident_winner():
    """A title is only as trustworthy as the least sure run that produced it."""
    rows = tr.tally_votes(
        [
            _run(("w1", "native", "આખેટ", "high")),
            _run(("w1", "native", "આખેટ", "low")),
        ],
        {"w1": "Gujarati"},
    )
    assert rows[0]["confidence"] == "low"


def test_a_run_that_dropped_the_row_did_not_vote():
    rows = tr.tally_votes(
        [_run(("w1", "native", "આખેટ", "high")), _run(), _run()], {"w1": "Gujarati"}
    )
    assert rows[0]["kind"] == "unknown"  # one vote is not agreement
    assert rows[0]["runs"] == 1


def test_a_work_no_run_answered_is_unknown_not_missing():
    rows = tr.tally_votes([_run(), _run()], {"w1": "Gujarati"})
    assert rows[0] == {
        "id": "w1",
        "kind": "unknown",
        "title": None,
        "confidence": "unknown",
        "votes": 0,
        "runs": 0,
    }
