from app.core.config import get_settings
from app.services.recommendation_service import _SYSTEM, _extract_json


async def test_recommendations_disabled_without_key(client, monkeypatch):
    """With no Anthropic key configured, the feature is dormant: enabled=False,
    no picks, no external call. Forced explicitly (not relying on the ambient
    .env) so a developer who has set a real key locally still sees this pass —
    the router and service both read get_settings() directly."""
    disabled = get_settings().model_copy(update={"anthropic_api_key": ""})
    monkeypatch.setattr("app.api.recommendations.get_settings", lambda: disabled)
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: disabled)

    resp = await client.get("/recommendations")
    assert resp.status_code == 200
    body = resp.json()
    assert body["enabled"] is False
    assert body["picks"] == []


def test_extract_json_pulls_the_array_out_of_surrounding_text():
    text = 'Sure! [{"work_id": "abc", "why": "You loved X."}] hope that helps'
    assert _extract_json(text) == [{"work_id": "abc", "why": "You loved X."}]


def test_extract_json_returns_empty_on_garbage():
    assert _extract_json("no json here") == []
    assert _extract_json("[not valid json}") == []


def test_system_prompt_formats_without_raising():
    """`_generate_picks` does `_SYSTEM.format(limit=...)`; the JSON example in
    the prompt must have its braces escaped or that raises KeyError at call
    time (only reachable with a real key — the disabled test never hits it).
    Renders it and checks the example survived intact."""
    rendered = _SYSTEM.format(limit=5)
    assert '{"work_id": "<id>", "why": "<sentence>"}' in rendered
    assert "Pick at most 5" in rendered
