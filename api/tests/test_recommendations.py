from app.services.recommendation_service import _extract_json


async def test_recommendations_disabled_without_key(client):
    """With no Anthropic key configured (the test default), the feature is
    dormant: enabled=False and no picks — and no external call is made."""
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
