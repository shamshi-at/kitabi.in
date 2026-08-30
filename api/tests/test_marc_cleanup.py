"""The MARC punctuation rules, tested against rows the live catalogue really has.

Every string below was taken from production (1,428 works / 1,174 authors /
1,021 publishers), not invented — including, deliberately, the ones that must
come back UNCHANGED. Each guard in `marc_cleanup` exists because some real row
would otherwise be corrupted, so the negative cases are the point of this file:
a cleanup that only proves it changes things proves the wrong half.
"""

import unicodedata

from app.services import marc_cleanup as mc

# --------------------------------------------------------------------------
# titles — things that SHOULD change
# --------------------------------------------------------------------------


def test_strips_the_terminal_period_every_marc_245_carries():
    fix = mc.clean_work("Gandhiji.")
    assert fix.title == "Gandhiji"
    assert fix.rules == [mc.TRAILING_PERIOD]
    assert fix.risk == mc.SAFE


def test_strips_a_balanced_pair_of_wrapping_quotes():
    assert mc.clean_work('"Mukajjiya kanasugaḷu"').title == "Mukajjiya kanasugaḷu"
    # An apostrophe inside is not a quote character of the same kind.
    assert mc.clean_work('"Me grandad \'ad an elephant!"').title == "Me grandad 'ad an elephant!"


def test_strips_a_dangling_parallel_title_marker():
    # `=` introduces a parallel title whose other half was never imported.
    fix = mc.clean_work("Sagar pataal ma safar =")
    assert fix.title == "Sagar pataal ma safar"
    assert fix.rules == [mc.DANGLING_SEPARATOR]


def test_splits_the_isbd_spaced_colon_into_a_subtitle():
    fix = mc.clean_work("Eat, pray, love : one woman's search for everything")
    assert fix.title == "Eat, pray, love"
    assert fix.subtitle == "one woman's search for everything"
    assert mc.SUBTITLE_SPLIT in fix.rules


def test_normalizes_decomposed_diacritics_to_nfc():
    # 352 of the 1,428 seeded titles store their diacritics decomposed while
    # the rest store them precomposed — identical to the eye, unequal to
    # Postgres, and a different regex match.
    decomposed = unicodedata.normalize("NFD", "Ādhunika Āndhrapradēś caritra")
    fix = mc.clean_work(decomposed)
    assert fix.rules == [mc.NFC]
    assert fix.title == unicodedata.normalize("NFC", decomposed)
    assert fix.title != decomposed


def test_drops_a_statement_of_responsibility_that_names_this_works_author():
    fix = mc.clean_work(
        "Mukajjiya kanasugaḷu",
        "raṅga rūpāntara, Es. Rāmamūrti",
        ("Es Rāmamūrti",),  # note: no period — matched through `fold`
    )
    assert fix.subtitle == "raṅga rūpāntara"
    assert mc.STATEMENT_OF_RESPONSIBILITY in fix.rules


def test_keeps_a_trailing_comma_phrase_that_is_not_an_author():
    fix = mc.clean_work("Māṇase", "arbhāṭa āni cillara", ("Es Rāmamūrti",))
    assert fix.subtitle == "arbhāṭa āni cillara"
    assert mc.STATEMENT_OF_RESPONSIBILITY not in fix.rules


# --------------------------------------------------------------------------
# titles — things that must NOT change
# --------------------------------------------------------------------------


def test_leaves_an_unspaced_colon_alone():
    # A departure time, a real title, and a real title. None of them are MARC.
    for title in (
        "4:50 phṛāoma Paidiṇgatana",
        "Death: Before, During & After... (In Kannada)",
        "Hannah: The Red Rose by the River",
    ):
        assert mc.clean_work(title).subtitle is None


def test_leaves_a_parallel_title_colon_alone():
    fix = mc.clean_work("Tamil̲ mutar̲pustakam =: Tamil first book")
    assert fix.subtitle is None


def test_leaves_an_authorial_ellipsis_alone():
    title = "yahi se ant h aur yahi se suruaat.."
    assert mc.clean_work(title).title == title


def test_does_not_strip_an_outer_quote_when_only_the_first_phrase_is_quoted():
    title = '"Hīro-hīro warasip", arathāta, Kalādhārī'
    assert mc.clean_work(title).title == title


def test_never_overwrites_a_subtitle_that_is_already_there():
    fix = mc.clean_work("Māṇase : arbhāṭa āni cillara", "a subtitle a reader typed")
    assert fix.title == "Māṇase : arbhāṭa āni cillara"
    assert fix.subtitle == "a subtitle a reader typed"


# --------------------------------------------------------------------------
# titles — flagged for a human, never fixed
# --------------------------------------------------------------------------


def test_flags_a_supplied_bracketed_heading_rather_than_unbracketing_it():
    # MARC brackets a heading the cataloguer supplied because the item had no
    # title page — which here means the row is not a book at all.
    fix = mc.clean_work("[South Asia pamphlet collection.")
    assert mc.BRACKETED_TITLE in fix.flags
    assert fix.title.startswith("[")


def test_flags_an_unbalanced_bracket():
    assert mc.UNBALANCED_BRACKET in mc.clean_name("Research Department, D.A.V. College]").flags


# --------------------------------------------------------------------------
# names
# --------------------------------------------------------------------------


def test_uninverts_a_filing_order_name_and_marks_it_for_review():
    fix = mc.clean_name("Basheer, Vaikom Muhammad", uninvert=True)
    assert fix.name == "Vaikom Muhammad Basheer"
    assert fix.rules == [mc.UNINVERT]
    assert fix.risk == mc.REVIEW  # reordering a person's name wants an eye


def test_uninverts_initials_and_native_script_too():
    assert mc.clean_name("Basham, A. L.", uninvert=True).name == "A. L. Basham"
    assert mc.clean_name("सावरकर, विनायक दामोदर", uninvert=True).name == "विनायक दामोदर सावरकर"


def test_strips_a_marc_date_qualifier_before_uninverting():
    fix = mc.clean_name("Karanth, Kota Shivarama, 1902-1997", uninvert=True)
    assert fix.name == "Kota Shivarama Karanth"
    assert fix.rules == [mc.MARC_DATES, mc.UNINVERT]


def test_moves_a_trailing_honorific_to_the_front_when_uninverting():
    """MARC files `Sarkar, Jadunath Sir`; nobody writes `Jadunath Sir Sarkar`."""
    assert mc.clean_name("Sarkar, Jadunath Sir", uninvert=True).name == "Sir Jadunath Sarkar"
    assert (
        mc.clean_name("Cutter, Harriet B. Low Mrs.", uninvert=True).name
        == "Mrs. Harriet B. Low Cutter"
    )
    # A nobiliary particle is not an honorific.
    assert mc.clean_name("Montaigne, Michel de", uninvert=True).name == "Michel de Montaigne"


def test_does_not_uninvert_on_a_comma_inside_a_parenthetical():
    # One body in one city — flipping would invent an organisation.
    name = "United States Information Service (Bombay, India)"
    fix = mc.clean_name(name, uninvert=True)
    assert fix.name == name
    assert mc.MULTI_COMMA_NAME in fix.flags


def test_does_not_uninvert_two_people_crammed_into_one_row():
    for name in ("Vijay Tendulkar,Priya Adarkar", "Tom Parks, Dan John Miller, Chris Lane"):
        fix = mc.clean_name(name, uninvert=True)
        assert fix.name == name
        assert mc.MULTI_COMMA_NAME in fix.flags


def test_does_not_uninvert_a_peerage():
    name = "Philip Dormer Stanhope, 4th Earl of Chesterfield"
    assert mc.clean_name(name, uninvert=True).name == name


def test_publishers_are_never_uninverted():
    # 55 of 1,021 seeded publisher names carry a comma; not one is an
    # inversion. They are departments and addresses.
    name = "Ramakrishna Vedanta Math, Publication Dept."
    assert mc.clean_name(name).name == name


def test_protects_a_trailing_period_that_belongs_to_an_initial():
    for name in ("എം. ടി.", "Khaṇdekara, Vi. Sa.", "Basham, A. L.", "Sharma, Suresh M.A."):
        assert mc.clean_name(name).name.endswith(".")


def test_protects_a_multi_letter_initial_by_the_company_it_keeps():
    """`Ti. Vai.` is திரு. வை. — a Dravidian initial three letters long.

    Found in the first production plan (31 Aug 2026), where a bare
    length-two rule kept the period on `Sa.` and stripped it off `Vai.` in the
    same catalogue. What marks an initials run is the token before it already
    ending in a period, not how short the last one happens to be.
    """
    assert mc.clean_name("Catācivapaṇṭārattār, Ti. Vai.").name.endswith("Vai.")
    # …but company alone is not enough: a real final word still loses its period.
    assert mc.clean_name("Vedas. Ṛgveda.").name == "Vedas. Ṛgveda"


def test_protects_a_trailing_period_that_belongs_to_an_abbreviation():
    for name in ("Bill Martin Jr.", "Arcade Pub.", "U.P.", "Bhar Printing, Inc."):
        assert mc.clean_name(name).name == name


def test_strips_a_trailing_period_from_an_ordinary_name():
    assert mc.clean_name("Balakumaran.").name == "Balakumaran"
    assert mc.clean_name("Rohtas Books.").name == "Rohtas Books"


# --------------------------------------------------------------------------
# invariants
# --------------------------------------------------------------------------


def test_cleaning_is_idempotent():
    """Running twice must equal running once — `apply` has to be re-runnable,
    and a rule that keeps finding work would loop the plan forever."""
    for title in (
        '"Mukajjiya kanasugaḷu"',
        "Gandhiji.",
        "Sagar pataal ma safar =",
        "Eat, pray, love : one woman's search for everything",
        "[Telugu novels.",
    ):
        once = mc.clean_work(title)
        twice = mc.clean_work(once.title, once.subtitle)
        assert twice.title == once.title
        assert twice.rules == []

    for name in (
        "Basheer, Vaikom Muhammad",
        "Karanth, Kota Shivarama, 1902-1997",
        # Two rules chaining on one row: MARC's terminal period sits AFTER the
        # dates, so a `$`-anchored date pattern that ignores it leaves work for
        # a second pass. Found by re-planning production after the first apply.
        "Govt. Central Press, 1974.",
    ):
        once = mc.clean_name(name, uninvert=True)
        twice = mc.clean_name(once.name, uninvert=True)
        assert twice.name == once.name
        assert twice.rules == []


def test_a_terminal_period_after_marc_dates_converges_in_one_pass():
    fix = mc.clean_name("Govt. Central Press, 1974.")
    assert fix.name == "Govt. Central Press"
    assert fix.rules == [mc.MARC_DATES]


def test_never_empties_a_field():
    for text in (".", '""', " : ", "=", "[]"):
        assert mc.clean_work(text).title
        assert mc.clean_name(text).name


def test_unchanged_rows_report_no_rules():
    assert mc.clean_work("Chemmeen").rules == []
    assert mc.clean_name("Vaikom Muhammad Basheer", uninvert=True).rules == []
