"""Cross-script search — a Latin query finds an Indic-script book and the
reverse ("Kayary" ↔ "കയർ"), through the stored romanized columns + pg_trgm.
Runs against real Postgres, so the trigram operators and the migration's
backfilled indexes are what's actually exercised."""

from app.services.translit import transliterate


def test_transliterate_romanizes_indic_and_lowercases_latin():
    assert transliterate("കയർ") == "kayar"
    assert transliterate("Chemmeen") == "chemmeen"
    assert transliterate("ഖസാക്കിന്റെ ഇതിഹാസം") == "khasakkinre itihasam"
    assert transliterate(None) is None
    assert transliterate("   ") is None


def test_itrans_nasal_tildes_never_reach_the_search_key():
    """ITRANS spells ങ/ഞ as ~N/~n. A tilde is not on anyone's keyboard, so it
    must not survive into a column readers' queries are matched against —
    doubled forms collapse to the spelling people actually type."""
    for source in ("ഞാൻ", "മാങ്ങാട്", "കൊഴിഞ്ഞു", "ശങ്കരൻ"):
        assert "~" not in transliterate(source)
    assert transliterate("ഞാൻ") == "njan"
    assert transliterate("മാങ്ങാട്") == "mangat"
    assert transliterate("കൊഴിഞ്ഞു") == "kozhinju"


def test_long_vowels_use_the_manglish_doubling():
    """ITRANS marks ീ/ൂ with an uppercase I/U that lowercasing flattens to a
    bare i/u — but nobody types Malayalam that way, and the single letter cost
    real matches: "Apoornn" scored 0.27 against "apurnnan" and found nothing
    (owner report, 23 Jul 2026)."""
    assert transliterate("അപൂർണ്ണൻ") == "apoornnan"
    assert transliterate("ചെമ്മീൻ") == "chemmeen"
    # The payoff: a Malayalam title and its Latin spelling now produce the
    # *same* key, so the two scripts meet exactly instead of merely near-missing.
    assert transliterate("ചെമ്മീൻ") == transliterate("Chemmeen")
    # Short vowels are untouched — കയർ stays the CLAUDE.md canonical example.
    assert transliterate("കയർ") == "kayar"


def test_tamil_uses_its_own_consonant_readings():
    """Tamil writes one letter per place of articulation (ப = pa/ba, ச =
    sa/cha/ja). The plain `tamil` scheme resolves those to Sanskrit voiced
    aspirates — "பொன்னியின் செல்வன்" became "bhonniyin jhelvan", which no
    reader could match (0.42 similarity against what they'd type, and 0.13 for
    சிலப்பதிகாரம்). The superscripted scheme gives the Tamil readings."""
    assert transliterate("பொன்னியின் செல்வன்") == "ponniyin chelvan"
    assert transliterate("சிலப்பதிகாரம்") == "chilappatikaram"
    assert transliterate("திருக்குறள்") == "tirukkural"


def test_other_indic_scripts_still_romanize():
    """The romanization is not Malayalam-only — every Brahmic script routes
    through the same ITRANS path, so the ee/oo and nasal fixes apply to all."""
    assert transliterate("మహాప్రస్థానం") == "mahaprasthanam"  # Telugu
    assert transliterate("ಕರ್ವಾಲೋ") == "karvalo"  # Kannada
    assert transliterate("গীতাঞ্জলি").startswith("geet")  # Bengali — long ee
    assert transliterate("गोदान") == "godana"  # Devanagari


async def _seed(client) -> None:
    for payload in (
        {
            "title": "കയർ",
            "author_names": ["തകഴി ശിവശങ്കരപ്പിള്ള"],
            "publisher_name": "ഡിസി ബുക്സ്",
        },
        {
            "title": "Chemmeen",
            "author_names": ["Thakazhi Sivasankara Pillai"],
            "publisher_name": "DC Books",
        },
    ):
        resp = await client.post("/catalog/works", json=payload)
        assert resp.status_code == 201


async def test_latin_query_finds_the_malayalam_title(client):
    await _seed(client)
    resp = await client.get("/catalog/search", params={"q": "Kayary"})
    titles = [w["title"] for w in resp.json()]
    assert "കയർ" in titles


async def test_malayalam_query_finds_the_latin_title(client):
    await _seed(client)
    resp = await client.get("/catalog/search", params={"q": "ചെമ്മീൻ"})
    titles = [w["title"] for w in resp.json()]
    assert "Chemmeen" in titles


async def test_latin_query_finds_the_malayalam_author(client):
    await _seed(client)
    resp = await client.get("/catalog/search/all", params={"q": "Thakazhi"})
    names = {a["name"] for a in resp.json()["authors"]}
    assert "തകഴി ശിവശങ്കരപ്പിള്ള" in names
    # …and the Malayalam author's book surfaces in the works section too.
    titles = {w["title"] for w in resp.json()["works"]}
    assert "കയർ" in titles


async def test_duplicate_detection_is_cross_script(client):
    await _seed(client)
    # Typing the romanized title in the add-book form must surface the
    # existing Malayalam book as a probable duplicate.
    resp = await client.get("/catalog/works/similar", params={"title": "Kayar"})
    titles = [w["title"] for w in resp.json()]
    assert "കയർ" in titles
