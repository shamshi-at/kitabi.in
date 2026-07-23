"""ALA-LC romanized Malayalam -> Malayalam script.

OpenLibrary stores Malayalam titles in the Library of Congress romanization
(`Kēraḷa sthalanāmakōśaṃ`) rather than native script, so a seeded catalog
displays romanized titles on every book page. That scheme is systematic, so it
converts back mechanically: `indic_transliteration` does the bulk via ISO
15919, with the ALA-LC-specific quirks handled here.

Converting also *improves* the search key: `title_translit` is recomputed from
the native script through ITRANS, which yields a more natural romanization
than stripping diacritics did (`manushya sahavasam`, not `manusya sahavasam`).

Four things ISO 15919 alone gets wrong, all verified against real seeded rows:

1. ALA-LC writes anusvara as ṃ (dot BELOW); ISO uses ṁ (dot above). Left
   alone it survives as a literal Latin ṃ in the output.
2. ALA-LC marks ഴ/റ with COMBINING LOW LINE (U+0332) — *not* the combining
   macron below (U+0331) one would expect, and no normal form folds either
   into the precomposed ISO letters.
3. Malayalam writes a syllable-final l/ḷ/n/ṇ/r as a chillu letter (വവ്വാൽ,
   not വവ്വാല്).
4. The underlined r̲ is ambiguous. Intervocalically it is റ (`nir̲aṅṅaḷ` =
   നിറങ്ങൾ, "colours" — plain ര would give നിരങ്ങൾ, "rows"), but after a
   consonant it is the second half of a cluster and plain ര (`pr̲aśnaṅṅaḷ` =
   പ്രശ്നങ്ങൾ, `yātr̲a` = യാത്ര). Resolved positionally below; the rule fits
   every occurrence in the seeded sample, but it is a heuristic, not a proof.
"""

import re
import unicodedata

from indic_transliteration import sanscript

# Latin combining sequences are written as escapes on purpose: pasted
# literally, a source file normalizes them into something that no longer
# matches the input.
_ANUSVARA = ("ṃ", "ṁ")  # ṃ (dot below, ALA-LC) -> ṁ (dot above, ISO)
_LOW_LINE = "̲"  # COMBINING LOW LINE — the mark ALA-LC actually uses
_ZHA = "ḻ"  # ḻ -> ഴ
_RRA = "ṟ"  # ṟ -> റ

_LATIN_VOWELS = set("aeiouāēīōūr̥")

# Syllable-final consonants take their chillu form. Applied word-finally only:
# mid-word, a virama-joined pair is usually a genuine conjunct (ണ് + ട = ണ്ട
# in രണ്ടു), and chillu-ing those would corrupt correct output.
_CHILLU = [("ല്", "ൽ"), ("ള്", "ൾ"), ("ന്", "ൻ"), ("ണ്", "ൺ"), ("ര്", "ർ")]
_WORD_END = r"(?=$|[\s\-–—,.;:!?()\[\]\"'/])"

# Coda r before a consonant is chillu ർ (അർക്ക), except before the semivowels,
# where ര് is a real onset conjunct (ര്യ in പര്യേഷണം).
_CODA_R = re.compile(r"ര്(?=[ക-ഹ])(?![യവരല])")

_MALAYALAM = re.compile(r"[ഀ-ൿ]")

# ISO->Malayalam renders ASCII digits as Malayalam numerals (2003 -> ൨൦൦൩).
# Those are archaic; modern Malayalam writes Arabic digits, so put them back.
_ML_DIGITS = str.maketrans("൦൧൨൩൪൫൬൭൮൯", "0123456789")

# A string carrying English function words is English, or a mixed name like
# "Mātr̥bhūmi Printing and Publishing Company". Converting the whole thing
# letter-by-letter produces പ്രിന്തിന്ഗ് അന്ദ് പുബ്ലിസ്ഹിന്ഗ് — Malayalam
# letters spelling English words, which is worse than leaving it romanized.
_ENGLISH_WORDS = re.compile(
    r"(?:^|\s)(and|of|the|for|with|from|in|on|by|a|an|its|their)(?:\s|$)", re.IGNORECASE
)


def _resolve_underlined_r(text: str) -> str:
    """r̲ -> ര after a consonant (cluster), റ after a vowel or at a word start."""
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "r" and i + 1 < len(text) and text[i + 1] == _LOW_LINE:
            # the last non-combining character before this r
            prev = ""
            j = len(out) - 1
            while j >= 0 and unicodedata.combining(out[j]):
                j -= 1
            if j >= 0:
                prev = out[j].lower()
            out.append("r" if prev and prev not in _LATIN_VOWELS else _RRA)
            i += 2
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def has_alalc_marks(text: str) -> bool:
    """True when [text] carries the romanization's diacritics — i.e. it is
    romanized Indic rather than a plain English title."""
    return any(unicodedata.combining(c) for c in unicodedata.normalize("NFD", text))


def to_malayalam_script(text: str | None) -> str | None:
    """Malayalam script for an ALA-LC romanized [text], or None when there is
    nothing to convert — already Malayalam, empty, or a plain-Latin title.

    Returning None for undiacriticked Latin is deliberate and load-bearing:
    a Malayalam-language work may carry a genuinely English title, and
    transliterating one produces convincing garbage (എf്fെച്ത്സ് ഒf് ഥെ).
    """
    if not text or not text.strip():
        return None
    src = unicodedata.normalize("NFC", text)
    if _MALAYALAM.search(src):
        return None  # already native script
    if not has_alalc_marks(src):
        return None  # plain English/Latin — leave it alone
    if _ENGLISH_WORDS.search(src):
        return None  # English, or a mixed name — see _ENGLISH_WORDS
    src = _resolve_underlined_r(src)
    src = src.replace("l" + _LOW_LINE, _ZHA).replace("n" + _LOW_LINE, "ṉ")
    src = src.replace("t" + _LOW_LINE, "t")  # no ISO equivalent; drop the bar
    src = src.replace(*_ANUSVARA)
    out = sanscript.transliterate(src.lower(), sanscript.ISO, sanscript.MALAYALAM)
    for seq, chillu in _CHILLU:
        out = re.sub(re.escape(seq) + _WORD_END, chillu, out)
    out = _CODA_R.sub("ർ", out).translate(_ML_DIGITS)
    return out if _MALAYALAM.search(out) else None
