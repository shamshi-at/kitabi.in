"""The OpenLibrary adapter, and the job's dormancy gate.

Driven entirely through `httpx.MockTransport`, so the whole adapter is
exercised without touching the network — the same shape as the cover
backfill's tests.

The adapter's job is *selection*: OpenLibrary's extraction quality for Indian
English is already 98.3% complete (measured 9 Sep 2026), so what can go wrong
here is fetching the wrong books, or assembling one book out of two rows.
"""

import httpx
import pytest

from app.core.config import get_settings
from app.jobs import catalog_intake as intake_job
from app.services import intake_openlibrary


def doc(
    key="/works/OL1W",
    title="An Era of Darkness",
    authors=("Shashi Tharoor",),
    isbn=("9789386021915", "9386021919"),
    publisher=("Aleph Book Company", "Rupa Publications"),
    cover=10866814,
    language=("eng",),
    pages=360,
):
    return {
        "key": key,
        "title": title,
        "author_name": list(authors),
        "first_publish_year": 2016,
        "editions": {
            "docs": [
                {
                    "key": "/books/OL32229526M",
                    "title": title,
                    "isbn": list(isbn),
                    "publisher": list(publisher),
                    "cover_i": cover,
                    "language": list(language),
                    "number_of_pages": pages,
                }
            ]
        },
    }


def _client(docs_by_seed=None, *, docs=None, fail=False):
    """A transport that answers every search with `docs`, or per-seed."""
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seed = request.url.params.get("q", "")
        calls.append(seed)
        if fail:
            return httpx.Response(503)
        payload = (docs_by_seed or {}).get(seed, docs if docs is not None else [])
        return httpx.Response(200, json={"docs": payload})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=5)
    client.calls = calls  # type: ignore[attr-defined]
    return client


@pytest.fixture(autouse=True)
def _no_sleeping(monkeypatch):
    """The adapter paces itself for OpenLibrary's sake; tests need not wait."""

    async def instant(_seconds):
        return None

    monkeypatch.setattr(intake_openlibrary.asyncio, "sleep", instant)


# --------------------------------------------------------------------------
# one edition, not a work plus an arbitrary printing
# --------------------------------------------------------------------------


async def test_the_isbn_publisher_and_cover_all_come_from_one_edition():
    """The 13 Aug 2026 lesson: `editions[0]` is a representative, never an
    answer. A title paired with some other printing's ISBN is a record that
    looks complete and is wrong."""
    async with _client(docs=[doc()]) as client:
        found = await intake_openlibrary.discover(client, seeds=('publisher:"Aleph Book Company"',))

    assert len(found) == 1
    got = found[0]
    assert got.isbn == "9789386021915"
    assert got.publisher == "Aleph Book Company"
    assert got.cover_url == "https://covers.openlibrary.org/b/id/10866814-L.jpg"
    assert got.page_count == 360


async def test_a_work_with_no_edition_is_skipped():
    """Nothing to take an ISBN from — a work-level record alone can never
    satisfy the gate, so it is not worth staging."""
    bare = {"key": "/works/OL9W", "title": "No editions", "author_name": ["X"]}
    async with _client(docs=[bare]) as client:
        assert await intake_openlibrary.discover(client, seeds=("q",)) == []


async def test_the_seeded_publisher_wins_among_an_editions_imprints():
    """An OL edition often lists three names for one house. The one we asked
    for is the most specific true answer and keeps our spelling consistent."""
    async with _client(docs=[doc(publisher=("Aleph", "Aleph Book Company"))]) as client:
        found = await intake_openlibrary.discover(client, seeds=('publisher:"Aleph Book Company"',))
    assert found[0].publisher == "Aleph Book Company"


async def test_without_a_publisher_seed_the_first_imprint_is_taken():
    async with _client(docs=[doc(publisher=("Rupa", "Aleph"))]) as client:
        found = await intake_openlibrary.discover(client, seeds=("subject:india",))
    assert found[0].publisher == "Rupa"


async def test_the_isbn13_is_preferred_when_the_edition_lists_both():
    async with _client(docs=[doc(isbn=("9386021919", "9789386021915"))]) as client:
        found = await intake_openlibrary.discover(client, seeds=("q",))
    assert found[0].isbn == "9789386021915"


# --------------------------------------------------------------------------
# selection
# --------------------------------------------------------------------------


async def test_a_non_latin_title_is_refused_by_the_english_adapter():
    """`language:eng subject:india` really does return a Devanagari कामसूत्र
    from a Spanish publisher (observed 9 Sep 2026). This adapter's whole claim
    is that it fetches English books."""
    async with _client(docs=[doc(title="कामसूत्र", language=())]) as client:
        assert await intake_openlibrary.discover(client, seeds=("q",)) == []


async def test_an_edition_in_another_language_is_refused():
    async with _client(docs=[doc(language=("mal",))]) as client:
        assert await intake_openlibrary.discover(client, seeds=("q",)) == []


async def test_a_latin_title_with_diacritics_is_kept():
    async with _client(docs=[doc(title="Café Naïve — a Memoir")]) as client:
        found = await intake_openlibrary.discover(client, seeds=("q",))
    assert len(found) == 1


async def test_one_work_found_by_two_seeds_is_claimed_once_by_the_first():
    """Seeds are ordered most-specific-first, so a publisher seed beats a
    subject one — and staging must not see the same book twice in one run."""
    seeds = ('publisher:"Aleph Book Company"', "subject:india")
    async with _client(docs_by_seed={s: [doc()] for s in seeds}) as client:
        found = await intake_openlibrary.discover(client, seeds=seeds)
    assert len(found) == 1
    assert found[0].publisher == "Aleph Book Company"


# --------------------------------------------------------------------------
# provenance and robustness
# --------------------------------------------------------------------------


async def test_provenance_matches_what_the_existing_seed_stamped():
    """`etl/03_transform.py` wrote `openlibrary` + the OL work key on 1,428
    works. An adapter that invented its own string would fail to recognise
    them and duplicate the lot."""
    async with _client(docs=[doc()]) as client:
        found = await intake_openlibrary.discover(client, seeds=("q",))
    assert found[0].provenance == ("openlibrary", "/works/OL1W")
    assert found[0].source_key == "/works/OL1W", "the work key, not the edition's"


async def test_a_failing_seed_costs_only_that_seed():
    """One bad query must not cost the whole night's intake."""
    seeds = ("bad", "good")

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.params.get("q") == "bad":
            return httpx.Response(503)
        return httpx.Response(200, json={"docs": [doc()]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        found = await intake_openlibrary.discover(client, seeds=seeds)
    assert len(found) == 1


async def test_malformed_json_is_survived():
    def handler(_request):
        return httpx.Response(200, content=b"not json")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        assert await intake_openlibrary.discover(client, seeds=("q",)) == []


async def test_the_search_asks_for_edition_subfields():
    """If the `editions.*` fields ever stop being requested, every candidate
    silently loses its ISBN and the whole run goes to `incomplete`."""
    async with _client(docs=[]) as client:
        await intake_openlibrary.discover(client, seeds=("q",))
    # one call, and the fields it asked for
    assert intake_openlibrary._FIELDS.count("editions.isbn") == 1
    assert "editions.publisher" in intake_openlibrary._FIELDS


# --------------------------------------------------------------------------
# the dormancy gate — the reason merging this to main creates nothing
# --------------------------------------------------------------------------


async def test_the_job_is_dormant_unless_explicitly_enabled(monkeypatch):
    """Off by default so a developer running the API on a laptop, a test
    database or a preview deploy never publishes a book. Production opts in
    via `ENV CATALOG_INTAKE_ENABLED=1` in the Dockerfile."""
    settings = get_settings().model_copy(update={"catalog_intake_enabled": False})
    monkeypatch.setattr(intake_job, "get_settings", lambda: settings)

    called = False

    def handler(_request):
        nonlocal called
        called = True
        return httpx.Response(200, json={"docs": []})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await intake_job.catalog_intake(client)

    assert called is False, "a dormant job must make no request at all"


def test_the_default_is_off():
    assert get_settings().catalog_intake_enabled is False


def test_the_job_is_registered_on_a_cron_not_an_interval(monkeypatch):
    """An interval job restarts from boot, and this service redeploys on every
    push to main — so a 24h interval would fire on each deploy. A daily budget
    that resets whenever someone ships is not a budget.

    Asserted against what `start()` actually registers, not against the source
    text: a test that greps the file passes on a comment.
    """
    from app.jobs import scheduler as sched

    registered: list[tuple] = []
    monkeypatch.setattr(sched.scheduler, "add_job", lambda *a, **k: registered.append((a, k)))
    monkeypatch.setattr(sched.scheduler, "start", lambda: None)
    sched.start()

    ours = [(a, k) for a, k in registered if k.get("id") == "catalog_intake"]
    assert len(ours) == 1, "the intake job must be registered exactly once"
    args, kwargs = ours[0]
    assert args[0] is intake_job.catalog_intake
    assert args[1] == "cron", "a daily budget must not reset on every deploy"
    assert kwargs["max_instances"] == 1
    assert kwargs["coalesce"] is True, "a missed night is one run, not a backlog of them"


def test_the_adapter_identifies_itself_to_the_sources_it_reads():
    """So an operator on the other end can see who is crawling and get in
    touch, rather than just blocking us."""
    agent = intake_job.USER_AGENT
    assert "kitabi.in" in agent
    # Header-safe: latin-1 is what httpx encodes headers as, and a stray
    # non-ASCII character here would fail every request at send time.
    agent.encode("latin-1")
    assert "\n" not in agent and "\r" not in agent


# --------------------------------------------------------------------------
# fixes found by the first live run (11 Sep 2026)
# --------------------------------------------------------------------------


async def test_the_work_cover_is_used_when_the_edition_has_none():
    """Without this the adapter held 26 of 50 live candidates for a missing
    cover: a specific edition row very often has no `cover_i` even when the
    work does. The fallback was written from the start and could never fire,
    because `cover_i` was not among the fields requested."""
    d = doc(cover=None)
    d["cover_i"] = 4242
    async with _client(docs=[d]) as client:
        found = await intake_openlibrary.discover(client, seeds=("q",))
    assert found[0].cover_url == "https://covers.openlibrary.org/b/id/4242-L.jpg"


async def test_the_edition_cover_still_wins_over_the_works():
    d = doc(cover=111)
    d["cover_i"] = 999
    async with _client(docs=[d]) as client:
        found = await intake_openlibrary.discover(client, seeds=("q",))
    assert "111" in found[0].cover_url


def test_the_work_level_cover_field_is_requested():
    """The fallback above is dead code unless the field is asked for — which
    is exactly how it shipped broken the first time."""
    assert ",cover_i," in f",{intake_openlibrary._FIELDS},"


async def test_a_publisher_seed_that_matched_a_different_house_is_dropped():
    """OpenLibrary's publisher search matches loosely:
    `publisher:"Juggernaut Books"` returns books from "Juggernaut Books Pty",
    an Australian press. The live run shelved an Australian YA novel under an
    Indian-English seed (11 Sep 2026)."""
    async with _client(docs=[doc(publisher=("Juggernaut Books Pty,",))]) as client:
        found = await intake_openlibrary.discover(client, seeds=('publisher:"Juggernaut Books"',))
    assert found == []


async def test_a_subject_seed_still_accepts_any_publisher():
    """The strict rule applies only where we named a house — a subject seed
    made no claim about the publisher, so it has nothing to contradict."""
    async with _client(docs=[doc(publisher=("Some Small Press",))]) as client:
        found = await intake_openlibrary.discover(client, seeds=("subject:india",))
    assert found[0].publisher == "Some Small Press"
