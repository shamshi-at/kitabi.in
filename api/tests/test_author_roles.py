"""Who wrote it and who translated it: asking a model, and not taking its word.

The model's part of this cannot be unit-tested and is not what these tests are
about. What is tested is the part that decides what gets **published**:
`judge`, which accepts an answer only when every role in it is backed by a
phrase that is really in the publisher's text, is about that person, and says
the right thing.

`fixtures/author_roles/recorded.json` is eleven real held books (Speaking
Tiger and HarperCollins India, 3 Oct 2026) — the question as it was really
asked and the answer the model really gave on 4 Oct. Five resolve; six stay
held, and one of those six is the reason the strictest rule here exists.
"""

import json
from pathlib import Path

import httpx
import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.models import FEATURE_AUTHOR_ROLES, CatalogIntake, LlmUsage, Work
from app.models.catalog_intake import STATE_COMPLETE, STATE_INCOMPLETE, STATE_PROMOTED
from app.services import author_roles, intake_gate, intake_service
from app.services.author_roles import Resolution, judge
from app.services.intake_gate import Candidate

RECORDED = json.loads(
    (Path(__file__).parent / "fixtures" / "author_roles" / "recorded.json").read_text()
)
BY_TITLE = {case["title"]: case for case in RECORDED}


def recorded(title_starts: str) -> dict:
    return next(case for title, case in BY_TITLE.items() if title.startswith(title_starts))


_RECORDED = object()


def verdict(case: dict, answer=_RECORDED) -> Resolution | None:
    return judge(
        case["answer"] if answer is _RECORDED else answer,
        tuple(case["names"]),
        case["blurb"],
        case["bios"],
    )


def credits(*rows) -> dict:
    return {"credits": [{"name": n, "role": r, "evidence": e} for n, r, e in rows]}


# --------------------------------------------------------------------------
# The recorded answers
# --------------------------------------------------------------------------


@pytest.mark.parametrize("case", RECORDED, ids=[c["title"][:32] for c in RECORDED])
def test_each_recorded_answer_gets_the_verdict_it_got(case):
    """The checker has not drifted: the same real answer over the same real
    text still resolves — or does not — exactly as it did."""
    result = verdict(case)
    assert (result.as_facts() if result else None) == case["resolved"]


def test_a_translated_novel_is_credited_to_its_author_and_its_translator():
    result = verdict(recorded("Diary of an Unseen Witness"))
    assert result == Resolution(authors=("Ampassayya Naveen",), translators=("Kalpana Kannabiran",))


def test_two_authors_are_two_authors():
    result = verdict(recorded("The House of Awadh"))
    assert result == Resolution(authors=("Aletta André", "Abhimanyu Kumar"))


def test_an_illustrator_is_recognised_and_not_credited_as_an_author():
    """The catalogue has authors and translators; an illustrator is neither,
    and is dropped rather than promoted to one."""
    result = verdict(recorded("Song of the Asunam"))
    assert result == Resolution(authors=("C.G. Salamander",))


def test_five_of_the_eleven_resolve_and_the_rest_stay_held():
    assert sum(1 for case in RECORDED if verdict(case)) == 5


def test_one_unknown_holds_the_whole_book():
    """`The Red Wind Howls`: the text names its author and says nothing of the
    other credited person. Publishing the author alone would silently drop a
    translator; publishing both as authors would be wrong. It waits."""
    case = recorded("The Red Wind Howls")
    roles = {c["name"]: c["role"] for c in case["answer"]["credits"]}
    assert roles == {"Christopher Peacock": "unknown", "Tsering Dondrup": "author"}
    assert verdict(case) is None


# --------------------------------------------------------------------------
# Answers that must not be believed
# --------------------------------------------------------------------------


def test_a_quote_that_is_not_in_the_text_is_not_evidence():
    case = recorded("Diary of an Unseen Witness")
    invented = credits(
        ("Ampassayya Naveen", "author", "Ampasayya Naveen’s landmark novel, Cheekati Rojulu"),
        ("Kalpana Kannabiran", "translator", "translated from the Telugu by Kalpana Kannabiran"),
    )
    assert verdict(case, invented) is None


def test_a_translator_needs_a_quote_about_translating():
    """A real phrase that names the person is not enough for this role: it has
    to say something about translating. Everything else here checks out, so
    this is the only rule that can refuse it."""
    names = ("Asha Menon", "Ravi Varma")
    blurb = "Asha Menon's first novel follows three sisters. Ravi Varma lives in Kochi."
    answer = credits(
        ("Asha Menon", "author", "Asha Menon's first novel follows three sisters"),
        ("Ravi Varma", "translator", "Ravi Varma lives in Kochi"),
    )
    assert judge(answer, names, blurb, {}) is None


def test_a_quote_that_names_nobody_does_not_say_whose_role_it_is():
    """`his debut novel` — whose? The first live run offered exactly this for
    `Those Boyhood Years`, and it was right, and it still does not count."""
    case = recorded("Those Boyhood Years")
    translator = next(c for c in case["answer"]["credits"] if c["role"] == "translator")
    pronoun = credits(
        (translator["name"], "translator", translator["evidence"]),
        ("Shibram Chakraborty", "author", "his debut novel"),
    )
    assert "his debut novel" in case["blurb"]  # it really is in the text
    assert verdict(case, pronoun) is None


def test_a_writer_whose_biography_lists_translations_is_not_thereby_the_author():
    """The near miss the strictest rule exists for. For `Desi Disruptors` the
    model offered its *translator* as an author, on the strength of "a
    full-time writer now" — a real phrase, from his own biography, which goes
    on to list what he has translated. Had the other name resolved, that would
    have been published."""
    case = recorded("Desi Disruptors")
    assert "translat" in case["bios"]["Vikrant Pande"].casefold()
    author_quote = case["bios"]["Vispy Doctor"].split(".")[0]
    both_authors = credits(
        ("Vispy Doctor", "author", author_quote),
        ("Vikrant Pande", "author", "a full-time writer now"),
    )
    assert verdict(case, both_authors) is None


def test_a_writer_out_of_a_sentence_about_translating_is_not_evidence_of_authorship():
    names = ("Asha Menon", "Ravi Varma")
    blurb = (
        "Asha Menon's first novel follows three sisters through one monsoon. "
        "Ravi Varma is a writer and translator who lives in Kochi."
    )
    trimmed = credits(
        ("Asha Menon", "author", "Asha Menon's first novel follows three sisters"),
        ("Ravi Varma", "author", "Ravi Varma is a writer"),
    )
    assert judge(trimmed, names, blurb, {}) is None
    honest = credits(
        ("Asha Menon", "author", "Asha Menon's first novel follows three sisters"),
        ("Ravi Varma", "translator", "Ravi Varma is a writer and translator"),
    )
    assert judge(honest, names, blurb, {}) == Resolution(
        authors=("Asha Menon",), translators=("Ravi Varma",)
    )


@pytest.mark.parametrize(
    "answer",
    [
        None,
        "not json",
        {"credits": "nope"},
        credits(
            ("Ampassayya Naveen", "author", "Ampasayya Naveen’s landmark novel")
        ),  # one missing
        credits(
            ("Ampassayya Naveen", "author", "Ampasayya Naveen’s landmark novel"),
            (
                "Somebody Else",
                "translator",
                "In Kalpana Kannabiran’s compelling English translation",
            ),
        ),  # a name nobody asked about
        credits(
            ("Ampassayya Naveen", "author", "Ampasayya Naveen’s landmark novel"),
            (
                "Kalpana Kannabiran",
                "narrator",
                "In Kalpana Kannabiran’s compelling English translation",
            ),
        ),  # not a role
    ],
    ids=["none", "string", "wrong-shape", "name-missing", "name-invented", "role-invented"],
)
def test_a_malformed_or_incomplete_answer_resolves_nothing(answer):
    assert verdict(recorded("Diary of an Unseen Witness"), answer) is None


def test_nobody_being_the_author_resolves_nothing():
    names = ("A Person", "B Person")
    blurb = "Translated by A Person. With illustrations by B Person, an illustrator."
    answer = credits(
        ("A Person", "translator", "Translated by A Person"),
        ("B Person", "illustrator", "illustrations by B Person"),
    )
    assert judge(answer, names, blurb, {}) is None


def test_an_anthology_is_filed_under_its_editors():
    names = ("Meena Pillai", "Arun Das")
    blurb = "Edited by Meena Pillai and Arun Das, this anthology gathers forty new voices."
    answer = credits(
        ("Meena Pillai", "editor", "Edited by Meena Pillai and Arun Das"),
        ("Arun Das", "editor", "Edited by Meena Pillai and Arun Das"),
    )
    assert judge(answer, names, blurb, {}) == Resolution(authors=("Meena Pillai", "Arun Das"))


def test_curly_quotes_and_spacing_do_not_defeat_a_real_quote():
    """A phrase copied out by a model and the page it came from rarely agree
    on apostrophes."""
    names = ("Asha Menon", "Ravi Varma")
    blurb = "Asha Menon’s  first novel. In Ravi Varma’s translation it finds English."
    answer = credits(
        ("Asha Menon", "author", "Asha Menon's first novel"),
        ("Ravi Varma", "translator", "In Ravi Varma's translation"),
    )
    assert judge(answer, names, blurb, {}) is not None


# --------------------------------------------------------------------------
# The request
# --------------------------------------------------------------------------


def _settings(**over):
    return get_settings().model_copy(update={"anthropic_api_key": "sk-test", **over})


def _reply(answer, stop_reason="end_turn"):
    return httpx.Response(
        200,
        json={
            "model": "claude-opus-5-5",
            "stop_reason": stop_reason,
            "content": [
                {"type": "thinking", "thinking": "", "signature": "sig"},
                {"type": "text", "text": json.dumps(answer)},
            ],
        },
    )


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=5)


async def _ask(client, case, settings=None):
    return await author_roles.ask(
        client,
        settings or _settings(),
        title=case["title"],
        names=tuple(case["names"]),
        blurb=case["blurb"],
        bios=case["bios"],
    )


async def test_the_request_is_shaped_for_the_model_it_is_sent_to():
    case = recorded("Dynasties Of Devotion")
    seen = {}

    def handler(request):
        seen["headers"] = request.headers
        seen["body"] = json.loads(request.content)
        return _reply(case["answer"])

    async with _client(handler) as client:
        answer = await _ask(client, case)

    body = seen["body"]
    assert answer == case["answer"]  # read past the thinking block to the text
    assert body["model"] == "claude-opus-5-5"
    # Thinking cannot be disabled on this model; sending the parameter is a 400.
    assert "thinking" not in body
    assert body["output_config"]["effort"] == "low"
    assert body["output_config"]["format"]["type"] == "json_schema"
    # A policy decline is re-run on the recommended fallback, not handed back.
    assert body["fallbacks"] == "default"
    assert seen["headers"]["anthropic-beta"] == "server-side-fallback-2026-07-01"
    assert seen["headers"]["x-api-key"] == "sk-test"
    question = body["messages"][0]["content"]
    assert "Deepa Mandlik" in question and "Aboli Mandlik" in question
    assert "biography of Aboli Mandlik" in question


@pytest.mark.parametrize("stop_reason", ["refusal", "max_tokens"])
async def test_a_refusal_or_a_cut_off_reply_is_no_answer(stop_reason):
    case = recorded("Dynasties Of Devotion")
    async with _client(lambda r: _reply(case["answer"], stop_reason)) as client:
        assert await _ask(client, case) is None


async def test_a_reply_with_no_text_block_is_no_answer():
    case = recorded("Dynasties Of Devotion")
    empty = httpx.Response(200, json={"stop_reason": "end_turn", "content": []})
    async with _client(lambda r: empty) as client:
        assert await _ask(client, case) is None


async def test_a_model_without_server_side_fallbacks_is_not_sent_the_parameter():
    case = recorded("Dynasties Of Devotion")
    seen = {}

    def handler(request):
        seen["headers"], seen["body"] = request.headers, json.loads(request.content)
        return _reply(case["answer"])

    async with _client(handler) as client:
        await _ask(client, case, _settings(author_roles_model="claude-sonnet-5"))
    assert "fallbacks" not in seen["body"]
    assert "anthropic-beta" not in seen["headers"]


# --------------------------------------------------------------------------
# The nightly pass
# --------------------------------------------------------------------------

SOURCE = "speakingtiger"


@pytest.fixture
async def session(db_sessionmaker):
    async with db_sessionmaker() as s:
        yield s


def held(case: dict, key: str = "1", **over) -> Candidate:
    base = dict(
        source=SOURCE,
        source_key=key,
        title=case["title"],
        contributors=tuple(case["names"]),
        description=case["blurb"],
        publisher="Speaking Tiger",
        isbn="9780060977498",
        cover_url="https://covers.openlibrary.org/b/id/1-L.jpg",
        language="English",
    )
    base.update(over)
    return Candidate(**base)


async def stage(session, *candidates) -> list[CatalogIntake]:
    await intake_service.record(session, list(candidates), source=SOURCE)
    return list((await session.execute(select(CatalogIntake))).scalars())


def counting(answer_for):
    """A fake Anthropic: `answer_for(question)` → the answer; `.calls` counts."""
    calls = []

    def handler(request):
        question = json.loads(request.content)["messages"][0]["content"]
        calls.append(question)
        return _reply(answer_for(question))

    handler.calls = calls
    return handler


async def test_a_held_book_is_released_with_its_author_and_translator(session):
    case = recorded("Diary of an Unseen Witness")
    (row,) = await stage(session, held(case))
    assert row.missing == [intake_gate.MISSING_AUTHOR_ROLES]
    handler = counting(lambda q: case["answer"])

    async with _client(handler) as client:
        counts = await author_roles.resolve_held(session, client, _settings(), limit=10)

    assert counts == {"resolved": 1}
    await session.refresh(row)
    assert row.state == STATE_COMPLETE
    assert row.payload["authors"] == ["Ampassayya Naveen"]
    assert row.payload["translators"] == ["Kalpana Kannabiran"]

    # …and published that way: the translator is the Work's translator.
    assert await intake_service.promote(session, limit=10) == {STATE_PROMOTED: 1}
    work = (await session.execute(select(Work))).scalar_one()
    assert [a.name for a in work.authors] == ["Ampassayya Naveen"]
    assert [t.name for t in work.translators] == ["Kalpana Kannabiran"]


async def test_every_question_is_metered_as_the_jobs_own_spend(session):
    """CLAUDE.md: a request that costs money is metered before it ships."""
    case = recorded("Diary of an Unseen Witness")
    await stage(session, held(case))
    async with _client(counting(lambda q: case["answer"])) as client:
        await author_roles.resolve_held(session, client, _settings(), limit=10)

    usage = (await session.execute(select(LlmUsage))).scalar_one()
    assert (usage.user_id, usage.feature, usage.count) == (
        author_roles.INTAKE_JOB_ID,
        FEATURE_AUTHOR_ROLES,
        1,
    )


async def test_a_book_is_asked_about_once_whatever_the_answer(session):
    """An unresolved book is not a reason to pay for the same answer nightly."""
    case = recorded("The Red Wind Howls")
    (row,) = await stage(session, held(case))
    handler = counting(lambda q: case["answer"])

    async with _client(handler) as client:
        first = await author_roles.resolve_held(session, client, _settings(), limit=10)
        second = await author_roles.resolve_held(session, client, _settings(), limit=10)

    assert first == {"unresolved": 1} and second == {}
    assert len(handler.calls) == 1
    await session.refresh(row)
    assert row.state == STATE_INCOMPLETE
    assert "asked" in row.note
    # The reply is kept for whoever looks at the row.
    assert row.payload[intake_service.ROLES_KEY]["answer"] == case["answer"]


async def test_the_resolution_survives_the_next_nights_crawl(session):
    """The feed still lists two names and no roles tomorrow."""
    case = recorded("Diary of an Unseen Witness")
    (row,) = await stage(session, held(case))
    async with _client(counting(lambda q: case["answer"])) as client:
        await author_roles.resolve_held(session, client, _settings(), limit=10)

    await stage(session, held(case))
    await intake_service.rescreen_incomplete(session)

    await session.refresh(row)
    assert row.state == STATE_COMPLETE
    assert row.payload["authors"] == ["Ampassayya Naveen"]


async def test_the_daily_ceiling_stops_the_asking(session):
    a, b = recorded("Diary of an Unseen Witness"), recorded("Those Boyhood Years")
    await stage(session, held(a, "1"), held(b, "2", isbn="9780143028109"))
    handler = counting(lambda q: a["answer"] if a["title"] in q else b["answer"])

    async with _client(handler) as client:
        counts = await author_roles.resolve_held(
            session, client, _settings(llm_daily_quota_author_roles=1), limit=10
        )

    assert len(handler.calls) == 1
    assert counts.get("over_budget") == 1


async def test_nothing_is_asked_without_a_key(session):
    """Rule 8: dormant, and no request leaves the process."""
    await stage(session, held(recorded("Diary of an Unseen Witness")))

    def explode(request):
        raise AssertionError("dormant without ANTHROPIC_API_KEY")

    async with _client(explode) as client:
        counts = await author_roles.resolve_held(
            session, client, _settings(anthropic_api_key=""), limit=10
        )
    assert counts == {}


async def test_a_book_waiting_on_something_else_too_is_not_worth_a_paid_call_yet(session):
    case = recorded("Diary of an Unseen Witness")
    await stage(session, held(case, cover_url=None))

    def explode(request):
        raise AssertionError("still missing a cover — asking now would be money for nothing")

    async with _client(explode) as client:
        assert await author_roles.resolve_held(session, client, _settings(), limit=10) == {}


async def test_a_failed_request_ends_the_pass_and_the_book_is_asked_again_later(session):
    case = recorded("Diary of an Unseen Witness")
    (row,) = await stage(session, held(case))

    async with _client(lambda r: httpx.Response(529)) as client:
        counts = await author_roles.resolve_held(session, client, _settings(), limit=10)
    assert counts == {"failed": 1}
    await session.refresh(row)
    assert intake_service.ROLES_KEY not in row.payload  # not marked as asked

    async with _client(counting(lambda q: case["answer"])) as client:
        assert await author_roles.resolve_held(session, client, _settings(), limit=10) == {
            "resolved": 1
        }


async def test_a_book_with_no_publisher_text_is_not_asked_about(session):
    case = recorded("Diary of an Unseen Witness")
    await stage(session, held(case, description=None))

    def explode(request):
        raise AssertionError("there is nothing for a model to read")

    async with _client(explode) as client:
        counts = await author_roles.resolve_held(session, client, _settings(), limit=10)
    assert counts == {"nothing_to_read": 1}


# --------------------------------------------------------------------------
# what the first night got wrong, and applying a new rule to old answers
# --------------------------------------------------------------------------


def test_an_edited_volume_beside_an_author_is_a_persons_call():
    """The one wrong answer of the first night (`Gems of Urdu Literature`,
    4 Oct 2026): the editor was rightly called the editor, and the other name
    was called the author on the strength of a *different* book he had written
    — so the book would have been filed under the wrong person and its editor
    dropped. Every quote was real; the combination is what cannot be trusted."""
    names = ("Meena Pillai", "Arun Das")
    blurb = (
        "Edited by Meena Pillai, this is a selection of forty short stories. "
        "Arun Das's best-loved novel, River Road, made his name."
    )
    answer = credits(
        ("Meena Pillai", "editor", "Edited by Meena Pillai"),
        ("Arun Das", "author", "Arun Das's best-loved novel, River Road"),
    )
    assert judge(answer, names, blurb, {}) is None


async def test_a_new_rule_is_applied_to_answers_already_given(session):
    """The reply is kept on the row, so tightening `judge` reaches books that
    were resolved under the old rules — before they are published, and without
    paying to ask again."""
    names = ("Meena Pillai", "Arun Das")
    blurb = (
        "Edited by Meena Pillai, this is a selection of forty short stories. "
        "Arun Das's best-loved novel, River Road, made his name."
    )
    answer = credits(
        ("Meena Pillai", "editor", "Edited by Meena Pillai"),
        ("Arun Das", "author", "Arun Das's best-loved novel, River Road"),
    )
    case = {"title": "Forty Stories", "names": list(names), "blurb": blurb}
    (row,) = await stage(session, held(case))
    # As the first night left it: resolved, and waiting to be published.
    intake_service.apply_roles(
        row, resolved={"authors": ["Arun Das"], "translators": []}, answer=answer
    )
    await session.commit()
    assert row.state == STATE_COMPLETE

    counts = await author_roles.rejudge(session)

    assert counts == {"no_longer_resolved": 1}
    await session.refresh(row)
    assert row.state == STATE_INCOMPLETE
    assert row.payload["authors"] == []
    assert row.missing == [intake_gate.MISSING_AUTHOR_ROLES]
    assert await intake_service.promote(session, limit=10) == {}

    def explode(request):
        raise AssertionError("re-judging must not ask, or pay, again")

    async with _client(explode) as client:
        assert await author_roles.resolve_held(session, client, _settings(), limit=10) == {}


async def test_rejudging_leaves_a_sound_answer_alone(session):
    case = recorded("Diary of an Unseen Witness")
    (row,) = await stage(session, held(case))
    async with _client(counting(lambda q: case["answer"])) as client:
        await author_roles.resolve_held(session, client, _settings(), limit=10)

    assert await author_roles.rejudge(session) == {}
    await session.refresh(row)
    assert row.state == STATE_COMPLETE
    assert row.payload["translators"] == ["Kalpana Kannabiran"]
