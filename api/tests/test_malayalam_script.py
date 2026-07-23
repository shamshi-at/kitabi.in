"""ALA-LC romanized Malayalam converts back to native script.

Every case here is a real title from the first production seed, so this
doubles as a regression net for the OpenLibrary romanization quirks that
`indic_transliteration` alone gets wrong.
"""

import pytest

from app.services.malayalam_script import has_alalc_marks, to_malayalam_script
from app.services.translit import transliterate


@pytest.mark.parametrize(
    ("romanized", "expected"),
    [
        ("Raṇṭu mudra", "രണ്ടു മുദ്ര"),
        # ṃ is ALA-LC anusvara (dot BELOW); ISO wants ṁ, else it survives as Latin.
        ("Kēraḷa sthalanāmakōśaṃ", "കേരള സ്ഥലനാമകോശം"),
        ("Manuṣya sahavāsaṃ", "മനുഷ്യ സഹവാസം"),
        # l̲ (COMBINING LOW LINE, not macron below) is ഴ.
        ("Kaṭamil̲ikkōṇukaḷ", "കടമിഴിക്കോണുകൾ"),
        # Word-final ḷ takes its chillu form ൾ, not ള്.
        ("Grāmavr̥kṣattile vavvāl", "ഗ്രാമവൃക്ഷത്തിലെ വവ്വാൽ"),
    ],
)
def test_converts_real_seeded_titles(romanized: str, expected: str):
    assert to_malayalam_script(romanized) == expected


@pytest.mark.parametrize(
    ("romanized", "expected"),
    [
        # After a consonant, r̲ closes a cluster and is plain ര …
        ("Kavitayuṭe pr̲aśnaṅṅaḷ", "കവിതയുടെ പ്രശ്നങ്ങൾ"),
        ("Tīrtthayātr̲a", "തീർത്ഥയാത്ര"),
        # … but after a vowel it is റ. "seven colours" — plain ര would give
        # നിരങ്ങൾ, which means rows.
        ("Ēl̲u nir̲aṅṅaḷ", "ഏഴു നിറങ്ങൾ"),
    ],
)
def test_underlined_r_resolves_by_position(romanized: str, expected: str):
    assert to_malayalam_script(romanized) == expected


def test_coda_r_becomes_chillu_but_conjuncts_survive():
    assert to_malayalam_script("Arkkapūrṇima") == "അർക്കപൂർണിമ"
    # ര്യ is a genuine onset conjunct — chillu-ing it would be wrong.
    assert to_malayalam_script("Paryēṣaṇaṃ") == "പര്യേഷണം"


@pytest.mark.parametrize(
    "untouched",
    [
        # A Malayalam-language work can carry an English title; transliterating
        # one yields convincing garbage (എf്fെച്ത്സ് ഒf് ഥെ), so refuse.
        "Effects of the Nine Astrological Planets",
        "കേരള",  # already native script
        "",
        None,
    ],
)
def test_returns_none_when_there_is_nothing_to_convert(untouched):
    assert to_malayalam_script(untouched) is None


def test_digits_stay_arabic():
    """ISO->Malayalam renders 2003 as ൨൦൦൩. Those numerals are archaic; modern
    Malayalam writes Arabic digits."""
    assert to_malayalam_script("Kēraḷa Ṭeliviṣan Avārḍ, 2003") == "കേരള ടെലിവിഷൻ അവാർഡ്, 2003"


def test_mixed_english_names_are_left_romanized():
    """A part-English name converts letter-by-letter into Malayalam spelling
    English words (പ്രിന്തിന്ഗ് അന്ദ് പുബ്ലിസ്ഹിന്ഗ്), which is worse than
    leaving it alone — so a string with English function words is refused."""
    assert to_malayalam_script("Mātr̥bhūmi Printing and Publishing Company") is None
    # …but a wholly Indic name with no such words still converts.
    assert to_malayalam_script("Sāhityapravarttaka Sahakaraṇasaṅghaṃ") == "സാഹിത്യപ്രവർത്തക സഹകരണസങ്ഘം"


def test_has_alalc_marks_distinguishes_romanized_from_plain():
    assert has_alalc_marks("Raṇṭu mudra")
    assert not has_alalc_marks("Effects of the Nine Astrological Planets")


def test_search_key_survives_conversion():
    """The romanized search column is recomputed from the native script, so
    converting must not break lookup — it should sharpen it."""
    assert transliterate(to_malayalam_script("Raṇṭu mudra")) == "rantu mudra"
    # ITRANS from native script romanizes ഷ as 'sh', which is closer to what a
    # reader types than the diacritic-stripped 'manusya' was.
    assert transliterate(to_malayalam_script("Manuṣya sahavāsaṃ")) == "manushya sahavasam"
