"""The ISBN-10 / ISBN-13 arithmetic, tested directly.

Every pair below is a real, mutually-checksum-valid ISBN — computed by hand and
cross-checked against the published examples — because a conversion tested only
against its own implementation proves nothing.
"""

from app.services import isbn

# (isbn10, isbn13) — genuine equivalents.
PAIRS = [
    ("8126403454", "9788126403455"),  # Chemmeen, DC Books — the repo's fixture ISBN
    ("0306406152", "9780306406157"),  # the ISBN spec's own worked example
    ("043942089X", "9780439420891"),  # check character X, the case that breaks naive parsers
    ("316148410X", "9783161484100"),  # already the fixture in test_fuzzy_search
]


def test_clean_accepts_the_forms_people_actually_paste():
    assert isbn.clean("978-81-264-0345-5") == "9788126403455"
    assert isbn.clean("978 81 264 0345 5") == "9788126403455"
    assert isbn.clean("ISBN: 8126403454") == "8126403454"
    assert isbn.clean('="9788126403455"') == "9788126403455"  # Goodreads CSV armour
    assert isbn.clean("043942089x") == "043942089X"  # lowercase check character


def test_clean_rejects_everything_that_is_not_an_isbn():
    assert isbn.clean("Chemmeen") is None
    assert isbn.clean("123456789") is None  # 9 digits
    assert isbn.clean("12345678901") is None  # 11 digits
    assert isbn.clean("978812640345X") is None  # X is only ever an ISBN-10 check char
    assert isbn.clean("") is None
    assert isbn.clean(None) is None
    assert isbn.clean(9788126403455) is None  # not a string


def test_checksums():
    for ten, thirteen in PAIRS:
        assert isbn.is_valid_isbn10(ten), ten
        assert isbn.is_valid_isbn13(thirteen), thirteen
    # One digit off in each direction.
    assert not isbn.is_valid_isbn10("8126403455")
    assert not isbn.is_valid_isbn13("9788126403454")
    # Right shape, wrong family.
    assert not isbn.is_valid_isbn10("9788126403455")
    assert not isbn.is_valid_isbn13("8126403454")


def test_conversion_round_trips():
    for ten, thirteen in PAIRS:
        assert isbn.to_isbn13(ten) == thirteen
        assert isbn.to_isbn10(thirteen) == ten
        # Passing the form you already have is a no-op, so callers need no branch.
        assert isbn.to_isbn13(thirteen) == thirteen
        assert isbn.to_isbn10(ten) == ten
        # Hyphenation is irrelevant to the arithmetic.
        assert isbn.to_isbn13("-".join([ten[:1], ten[1:]])) == thirteen


def test_979_has_no_isbn10():
    """The 979 range exists because 978 ran out — there is nothing to map to,
    and inventing one would produce a number that belongs to another book."""
    assert isbn.is_valid_isbn13("9791234567896")
    assert isbn.to_isbn10("9791234567896") is None
    assert isbn.variants("9791234567896") == ["9791234567896"]


def test_conversion_refuses_to_guess_from_a_bad_checksum():
    """A mis-keyed ISBN converted anyway yields a *valid* ISBN for a different
    book — the worst possible failure, because nothing downstream can detect it."""
    assert isbn.to_isbn13("8126403455") is None
    assert isbn.to_isbn10("9788126403454") is None


def test_canonical_prefers_isbn13():
    for ten, thirteen in PAIRS:
        assert isbn.canonical(ten) == thirteen
        assert isbn.canonical(thirteen) == thirteen
    assert isbn.canonical("979-1-234-56789-6") == "9791234567896"


def test_canonical_keeps_a_checksum_invalid_isbn_rather_than_dropping_it():
    """Real catalogues contain misprinted ISBNs. Storing None instead loses the
    only edition identifier we have; storing it as given keeps it findable."""
    assert isbn.canonical("8126403455") == "8126403455"
    assert isbn.canonical("9788126403454") == "9788126403454"
    assert isbn.canonical("not an isbn") is None


def test_variants_covers_both_forms():
    for ten, thirteen in PAIRS:
        assert set(isbn.variants(ten)) == {ten, thirteen}
        assert set(isbn.variants(thirteen)) == {ten, thirteen}
        # The form the caller supplied leads, so a caller that takes the first
        # match gets the one it asked about.
        assert isbn.variants(ten)[0] == ten
        assert isbn.variants(thirteen)[0] == thirteen


def test_variants_still_finds_a_row_stored_with_a_bad_checksum():
    assert isbn.variants("8126403455") == ["8126403455"]
    assert isbn.variants("Chemmeen") == []


def test_looks_like_isbn_is_shape_only():
    assert isbn.looks_like_isbn("978-81-264-0345-5")
    assert isbn.looks_like_isbn("8126403455")  # bad checksum, still an ISBN-shaped query
    assert not isbn.looks_like_isbn("Chemmeen")
    assert not isbn.looks_like_isbn(None)
