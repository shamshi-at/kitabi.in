"""MARC cataloguing punctuation -> reader-facing text.

Most of the seeded catalogue did not come from a bookshop feed. For every
Indic language except Malayalam, OpenLibrary's records originate in US
research-library MARC — the Library of Congress South Asia Cooperative
Acquisitions Program — and those fields are transcribed under cataloguing
rules, not written for a reader. So the catalogue carries titles like
`"Mukajjiya kanasugaḷu"` (245$a, quotes and all), `Gandhiji.` (the terminal
period every MARC 245 ends with), `Sagar pataal ma safar =` (a parallel-title
marker whose other half was never imported), and authors filed as
`Basheer, Vaikom Muhammad` because a card catalogue sorts by surname.

None of that is *wrong* data — it is the right data in the wrong dialect. This
module translates it, and only the part that translates mechanically:
punctuation, Unicode normalization, and word order. It does not touch the
romanization itself (`Mukajjiya kanasugaḷu` stays romanized here — converting
it back to ಮುಕಜ್ಜಿಯ ಕನಸುಗಳು is services/malayalam_script's job, still
Malayalam-only) and it does not judge whether a record deserves to be in the
catalogue at all.

Two rules the whole module is built around:

1. **Every function is pure and returns what it did.** Callers get the rule
   names that fired, so a plan file can be reviewed rule-by-rule and a receipt
   can be reverted exactly. Nothing here reads or writes a database.
2. **When a fix needs a judgement, it is not a fix — it is a flag.** A
   bracketed `[South Asia pamphlet collection.` title is a supplied heading
   for something that is not a book; un-bracketing it would make it *look*
   more legitimate without making it more true. Those come back in `flags`
   for a human, never in `text`.

Risk is reported per change, mirroring 08_genre_classify's confidences: SAFE
changes are mechanical, REVIEW changes (only ever un-inversion) reorder a
human name and want an eye on them before they are written.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

from app.services.translit import fold

# --- rule names -----------------------------------------------------------
# Stable strings: they are written into plan and receipt files, so a run from
# last month must still be greppable and revertible. Never rename one in place.
NFC = "nfc"
WHITESPACE = "whitespace"
UNQUOTE = "unquote"
DANGLING_SEPARATOR = "dangling_separator"
TRAILING_PERIOD = "trailing_period"
SUBTITLE_SPLIT = "subtitle_split"
STATEMENT_OF_RESPONSIBILITY = "statement_of_responsibility"
MARC_DATES = "marc_dates"
UNINVERT = "uninvert"

# --- flags (reported, never applied) --------------------------------------
BRACKETED_TITLE = "bracketed_title"
MULTI_COMMA_NAME = "multi_comma_name"
UNBALANCED_BRACKET = "unbalanced_bracket"

SAFE = "safe"
REVIEW = "review"
RISKS = (SAFE, REVIEW)

_WS = re.compile(r"\s+")

# The separators MARC leaves dangling when the field they introduce was never
# imported: ` /` before a statement of responsibility, ` =` before a parallel
# title, ` :` before a subtitle, and the ISBD `;`. Measured on the live
# catalogue: 28 titles end in a bare `=`, e.g. `Sagar pataal ma safar =`.
_DANGLING = re.compile(r"[\s]*[/=:;,]+\s*$")

# A trailing period is stripped only when the last word can't be an initial or
# an abbreviation. Three guards, each earned against a real row:
#   - `..`/`...` is authorial, not MARC (`yahi se ant h aur yahi se suruaat..`)
#   - a final token of one or two letters is an initial (`എം. ടി.`,
#     `Khaṇdekara, Vi. Sa.`, `Basham, A. L.`) — stripping it corrupts the name
#   - a token containing its own period is an abbreviation (`U.P.`, `M.A.`)
_ABBREVIATIONS = frozenset(
    """jr sr ed eds comp comps trans tr dept dep inc ltd pvt co pub publ
       bros univ vol vols no nos pt pts st mr mrs ms dr prof rev hon
       etc ca cf al""".split()
)

# MARC qualifies a heading with the person's dates or floruit. They belong in
# an authority record, not under a book cover: `Karanth, Kota Shivarama,
# 1902-1997` reads as a database row, and the year is already on the work.
# The trailing `.?` matters: MARC ends the field with a period *after* the
# dates (`Govt. Central Press, 1974.`), and an anchored pattern without it
# simply fails to match until some other rule has removed that period — which
# means the row needs two passes to converge. Caught by re-planning production
# after the first apply, 31 Aug 2026; a cleanup that only settles on the second
# run is a cleanup nobody can tell is finished.
_MARC_DATE_SUFFIX = re.compile(
    r",\s*(?:b\.|d\.|fl\.|ca\.|approximately|active)?\s*\d{3,4}\??\s*-?\s*\d{0,4}\??\s*\.?\s*$",
    re.IGNORECASE,
)

_DIGIT = re.compile(r"\d")

# An honorific filed at the end of the given-name half belongs at the FRONT of
# the reader-facing name, not wherever the flip happens to leave it: MARC files
# `Sarkar, Jadunath Sir`, and a naive un-inversion yields `Jadunath Sir Sarkar`
# — not wrong exactly, but not how anyone writes it either.
_HONORIFICS = frozenset("sir mr mrs ms dr prof rev sri smt shri".split())


@dataclass
class Fix:
    """What cleaning one row produced. `rules` is empty when nothing changed."""

    title: str | None = None
    subtitle: str | None = None
    name: str | None = None
    rules: list[str] = field(default_factory=list)
    flags: list[str] = field(default_factory=list)

    @property
    def changed(self) -> bool:
        return bool(self.rules)

    @property
    def risk(self) -> str:
        """SAFE unless some rule that fired reorders a human name."""
        return REVIEW if UNINVERT in self.rules else SAFE


# --------------------------------------------------------------------------
# shared primitives
# --------------------------------------------------------------------------


def _normalize(text: str, rules: list[str]) -> str:
    """NFC + collapsed whitespace.

    NFC is not cosmetic here. 354 of the 1,428 seeded titles store their
    diacritics decomposed (`Ādhunika` as A + COMBINING MACRON) while the rest
    store them precomposed, so two titles that look identical compare unequal,
    sort apart, and match different regexes. Whichever form a row happens to
    carry is an accident of which import wrote it.
    """
    out = unicodedata.normalize("NFC", text)
    if out != text:
        rules.append(NFC)
    collapsed = _WS.sub(" ", out).strip()
    if collapsed != out:
        rules.append(WHITESPACE)
    return collapsed


def _strip_dangling(text: str, rules: list[str]) -> str:
    out = _DANGLING.sub("", text)
    if out != text:
        rules.append(DANGLING_SEPARATOR)
    return out


def _protected_final_token(text: str) -> bool:
    """Whether the last word makes a trailing period load-bearing."""
    words = text[:-1].split()
    if not words:
        return True
    last = words[-1]
    if "." in last:  # U.P. , M.A. , Ph.D
        return True
    bare = last.strip("().,'\"")
    if len(bare) <= 2 or bare.lower() in _ABBREVIATIONS:
        return True
    # An initial is recognisable by company, not only by length. Devanagari and
    # Dravidian initials romanize to three and four letters — `Ti. Vai.` is
    # திரு. வை., `Ba. Na.` is ಬ. ನ. — so a bare length rule strips the period
    # off `Vai.` while keeping it on `Sa.`, which is arbitrary. What actually
    # marks the run is the token BEFORE it already ending in a period.
    return len(words) > 1 and words[-2].endswith(".") and len(bare) <= 4


def _strip_trailing_period(text: str, rules: list[str]) -> str:
    if not text.endswith(".") or text.endswith("..") or _protected_final_token(text):
        return text
    rules.append(TRAILING_PERIOD)
    return text[:-1].rstrip()


def _bracket_flags(text: str) -> list[str]:
    """Bracket damage worth a human's attention, never fixed here.

    A leading `[` is MARC's mark for a heading the cataloguer supplied because
    the item had no title page — which in this catalogue means the row is not a
    book (`[South Asia pamphlet collection.`, `[Telugu novels.`). An unbalanced
    bracket anywhere is a truncated import (`Research Department, D.A.V.
    College]`). Both want deleting or re-sourcing, not tidying.
    """
    flags = []
    if text.startswith("[") or text.startswith("("):
        flags.append(BRACKETED_TITLE)
    for open_c, close_c in (("[", "]"), ("(", ")")):
        if text.count(open_c) != text.count(close_c):
            flags.append(UNBALANCED_BRACKET)
            break
    return flags


# --------------------------------------------------------------------------
# titles
# --------------------------------------------------------------------------


def _unquote(text: str, rules: list[str]) -> str:
    """Strip a balanced pair of wrapping quotes.

    Balance is the whole guard. `"Mukajjiya kanasugaḷu"` is a quoted title;
    `"Hīro-hīro warasip", arathāta, Kalādhārī, kalādhārīpūjā` is a title whose
    *first phrase* is quoted, and stripping its outer quote would leave a
    stray one behind. So: opens and closes with the same quote, and carries
    exactly that pair.
    """
    for quote in ('"', "“”", "'"):
        open_c, close_c = (quote[0], quote[-1])
        if len(text) > 2 and text.startswith(open_c) and text.endswith(close_c):
            inner = text[1:-1]
            if open_c not in inner and close_c not in inner:
                rules.append(UNQUOTE)
                return inner.strip()
    return text


def _split_subtitle(title: str, rules: list[str]) -> tuple[str, str | None]:
    """`Title : subtitle` -> (title, subtitle), on the ISBD spaced colon only.

    Spaced is the guard, and it does all the work: `Death: Before, During &
    After`, `Hannah: The Red Rose by the River` and `4:50 phṛāoma Paidiṇgatana`
    are a real title, a real title and a *departure time* — none of them are
    MARC, and none of them are spaced. `Tamil̲ mutar̲pustakam =: Tamil first
    book` is a parallel title rather than a subtitle, so the `=` disqualifies
    it too.
    """
    if title.count(" : ") != 1 or " =: " in title:
        return title, None
    left, right = title.split(" : ", 1)
    if not left.strip() or not right.strip():
        return title, None
    rules.append(SUBTITLE_SPLIT)
    return left.strip(), right.strip()


def _drop_statement_of_responsibility(
    subtitle: str, author_names: tuple[str, ...], rules: list[str]
) -> str:
    """Drop a trailing `, <author>` that MARC 245$c left in the subtitle.

    Only when the tail actually *is* one of this work's authors, compared
    through `fold` so `Es. Rāmamūrti` matches the stored `Es Rāmamūrti`. That
    check is what keeps this deterministic: without it the rule would be
    "delete whatever follows the last comma", which would eat real subtitles.
    """
    if "," not in subtitle or not author_names:
        return subtitle
    head, _, tail = subtitle.rpartition(",")
    tail_fold = fold(tail.strip())
    if not head.strip() or not tail_fold:
        return subtitle
    if any(tail_fold == fold(name) for name in author_names):
        rules.append(STATEMENT_OF_RESPONSIBILITY)
        return head.strip()
    return subtitle


def clean_work(
    title: str,
    subtitle: str | None = None,
    author_names: tuple[str, ...] = (),
) -> Fix:
    """Reader-facing title and subtitle for one work's MARC-derived fields.

    `subtitle` is only ever *filled* when it was empty — a work that already
    has one keeps it, because the split would otherwise overwrite a subtitle a
    reader typed with one derived from a title.
    """
    rules: list[str] = []
    flags = _bracket_flags(title.strip())

    new_title = _normalize(title, rules)
    new_title = _unquote(new_title, rules)
    new_title = _strip_dangling(new_title, rules)

    split_off: str | None = None
    if not (subtitle or "").strip():
        new_title, split_off = _split_subtitle(new_title, rules)
    new_title = _strip_trailing_period(new_title, rules)

    raw_subtitle = split_off if split_off is not None else subtitle
    new_subtitle: str | None = None
    if raw_subtitle and raw_subtitle.strip():
        sub_rules: list[str] = []
        new_subtitle = _normalize(raw_subtitle, sub_rules)
        new_subtitle = _strip_dangling(new_subtitle, sub_rules)
        new_subtitle = _strip_trailing_period(new_subtitle, sub_rules)
        new_subtitle = _drop_statement_of_responsibility(new_subtitle, author_names, sub_rules)
        # The split already recorded itself; its own tidying is not a second
        # change to review.
        rules.extend(r for r in sub_rules if r not in rules)
        new_subtitle = new_subtitle or None

    # A rule that empties a title has misfired on a row we do not understand —
    # drop the whole fix rather than write a blank into a published page.
    if not new_title:
        return Fix(title=title, subtitle=subtitle, rules=[], flags=[*flags, UNBALANCED_BRACKET])

    unchanged = new_title == title and (new_subtitle or None) == (subtitle or None)
    return Fix(
        title=new_title,
        subtitle=new_subtitle,
        rules=[] if unchanged else rules,
        flags=flags,
    )


# --------------------------------------------------------------------------
# names
# --------------------------------------------------------------------------


def _comma_outside_brackets(name: str) -> int | None:
    """Index of the single top-level comma, or None if there isn't exactly one.

    Depth matters because the corporate headings in this catalogue put their
    comma inside a parenthetical: `United States Information Service (Bombay,
    India)` is one body in one city, and flipping on that comma would invent
    an organisation called "India) United States Information Service (Bombay".
    """
    depth = 0
    found = None
    for i, ch in enumerate(name):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth = max(0, depth - 1)
        elif ch == "," and depth == 0:
            if found is not None:
                return None
            found = i
    return found


def _uninvert(name: str, rules: list[str], flags: list[str]) -> str:
    """`Surname, Given` -> `Given Surname`, when it is safely that shape.

    Card catalogues file by surname; a book cover does not. Every guard below
    exists because a real row would otherwise be corrupted:

      - the comma must be top-level         (the parenthetical corporate names)
      - it must be followed by a space      (`Vijay Tendulkar,Priya Adarkar` is
                                             two people crammed into one row)
      - there must be exactly one           (`Tom Parks, Dan John Miller,
                                             Christopher Lane` is three)
      - no digits on the right              (`Philip Dormer Stanhope, 4th Earl
                                             of Chesterfield` is a peerage)
      - at most four words on the right     (same row, second guard)

    Anything that fails them is flagged, not guessed at.
    """
    comma = _comma_outside_brackets(name)
    if comma is None:
        if "," in name:
            flags.append(MULTI_COMMA_NAME)
        return name
    surname, given = name[:comma].strip(), name[comma + 1 :]
    if not given.startswith(" "):
        flags.append(MULTI_COMMA_NAME)
        return name
    given = given.strip()
    if not surname or not given or _DIGIT.search(given) or len(given.split()) > 4:
        flags.append(MULTI_COMMA_NAME)
        return name
    rules.append(UNINVERT)
    words = given.split()
    if len(words) > 1 and words[-1].rstrip(".").lower() in _HONORIFICS:
        return f"{words[-1]} {' '.join(words[:-1])} {surname}"
    return f"{given} {surname}"


def clean_name(name: str, *, uninvert: bool = False) -> Fix:
    """Reader-facing form of an author or publisher name.

    `uninvert` is off by default and must stay off for publishers: 55 of the
    1,021 seeded publisher names carry a comma, and not one of them is an
    inversion — they are departments and addresses (`Ramakrishna Vedanta Math,
    Publication Dept.`), which the rule would reverse into nonsense. Inversion
    is a rule about *people*.
    """
    rules: list[str] = []
    flags = _bracket_flags(name.strip())

    out = _normalize(name, rules)
    stripped = _MARC_DATE_SUFFIX.sub("", out).rstrip(" ,")
    if stripped and stripped != out:
        rules.append(MARC_DATES)
        out = stripped
    out = _strip_trailing_period(out, rules)
    if uninvert:
        out = _uninvert(out, rules, flags)

    if not out:
        return Fix(name=name, rules=[], flags=[*flags, UNBALANCED_BRACKET])
    return Fix(name=out, rules=[] if out == name else rules, flags=flags)
