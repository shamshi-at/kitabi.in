"""Reading an Anthropic /v1/messages reply without assuming block 0 is text.

The regression these cover: `content[0]["text"]` 500'd `/catalog/cover-extract`
in production (26 Jul 2026) the moment the model thought before answering — a
`thinking` block has no `text` key. A refusal is the same class of hazard from
the other direction: HTTP 200, empty `content`.
"""

import httpx
import pytest

from app.core.config import Settings
from app.services.anthropic_client import headers, reply_text
from app.services.extraction_service import extract_from_covers
from app.services.recommendation_service import _generate_picks

_BUCKET = "https://proj.supabase.co/storage/v1/object/public/covers"

# The shapes below are real: captured from claude-sonnet-5 against the live API.
_THINKING_FIRST = {
    "stop_reason": "end_turn",
    "content": [
        {"type": "thinking", "thinking": "The cover reads...", "signature": "abc123"},
        {"type": "text", "text": '{"title": "Chemmeen"}'},
    ],
}
_THINKING_ONLY = {
    "stop_reason": "max_tokens",
    "content": [{"type": "thinking", "thinking": "Still deliberating", "signature": "x"}],
}
_REFUSED = {"stop_reason": "refusal", "content": []}


def test_reply_text_skips_a_leading_thinking_block():
    assert reply_text(_THINKING_FIRST) == '{"title": "Chemmeen"}'


def test_reply_text_is_empty_when_no_block_carries_text():
    # Thinking ate the whole token budget; a refusal returns nothing at all.
    assert reply_text(_THINKING_ONLY) == ""
    assert reply_text(_REFUSED) == ""


def test_reply_text_tolerates_junk_rather_than_raising():
    assert reply_text({}) == ""
    assert reply_text({"content": None}) == ""
    assert reply_text({"content": ["not a block"]}) == ""
    assert reply_text({"content": [{"type": "text"}]}) == ""  # text key missing
    assert reply_text(None) == ""


def test_headers_carry_the_key_and_api_version():
    sent = headers(Settings(anthropic_api_key="test-key"))
    assert sent["x-api-key"] == "test-key"
    assert sent["anthropic-version"] == "2023-06-01"


def _faking(payload: dict) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _req: httpx.Response(200, json=payload))
    )


@pytest.mark.anyio
async def test_extraction_reads_past_a_thinking_block():
    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with _faking(_THINKING_FIRST) as fake:
        fields = await extract_from_covers(
            settings, front_url=f"{_BUCKET}/front.jpg", back_url=None, client=fake
        )
    assert fields["title"] == "Chemmeen"


@pytest.mark.anyio
@pytest.mark.parametrize("payload", [_THINKING_ONLY, _REFUSED])
async def test_extraction_returns_empty_fields_instead_of_500(payload):
    """The reader gets an unprefilled form, not a 502 from a crashed router."""
    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with _faking(payload) as fake:
        fields = await extract_from_covers(
            settings, front_url=f"{_BUCKET}/front.jpg", back_url=None, client=fake
        )
    assert fields["title"] is None
    assert fields["authors"] == []


@pytest.mark.anyio
async def test_extraction_disables_thinking_so_the_budget_buys_json():
    """`max_tokens` caps thinking and prose together — a thinking model can
    spend it all and return no text. Assert the request says so explicitly."""
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        captured.update(json.loads(request.content))
        return httpx.Response(200, json={"content": [{"type": "text", "text": "{}"}]})

    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as fake:
        await extract_from_covers(
            settings, front_url=f"{_BUCKET}/front.jpg", back_url=None, client=fake
        )

    assert captured["thinking"] == {"type": "disabled"}
    assert captured["max_tokens"] >= 2048


@pytest.mark.anyio
async def test_recommendations_read_past_a_thinking_block():
    payload = {
        "content": [
            {"type": "thinking", "thinking": "Weighing the ratings", "signature": "x"},
            {"type": "text", "text": '[{"work_id": "w1", "why": "You loved Chemmeen."}]'},
        ]
    }
    settings = Settings(anthropic_api_key="test-key")
    async with _faking(payload) as fake:
        picks = await _generate_picks(settings, rated=[], candidates=[], limit=5, client=fake)
    assert picks == [{"work_id": "w1", "why": "You loved Chemmeen."}]


@pytest.mark.anyio
async def test_recommendations_return_nothing_on_a_refusal():
    settings = Settings(anthropic_api_key="test-key")
    async with _faking(_REFUSED) as fake:
        assert await _generate_picks(settings, rated=[], candidates=[], limit=5, client=fake) == []
