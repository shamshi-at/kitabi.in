"""Cover-photo extraction: the gate (dormant without a key), URL restriction,
and the service's parsing/cleaning — the LLM call itself is faked via
httpx.MockTransport, mirroring the recommendations tests."""

import httpx
import pytest

from app.core.config import Settings, get_settings
from app.services.extraction_service import (
    _clean,
    _extract_object,
    allowed_image_url,
    extract_from_covers,
    valid_isbn13,
)

_BUCKET = "https://proj.supabase.co/storage/v1/object/public/covers"


async def test_cover_extract_disabled_without_key(client, monkeypatch):
    """Forced disabled regardless of the ambient .env (a developer may have a
    real key set locally) — the endpoint reads get_settings() directly."""
    disabled = get_settings().model_copy(update={"anthropic_api_key": ""})
    monkeypatch.setattr("app.api.catalog.get_settings", lambda: disabled)

    resp = await client.post("/catalog/cover-extract", json={"front_url": f"{_BUCKET}/x.jpg"})
    assert resp.status_code == 503
    # The global handler flattens structured detail to the top level.
    assert resp.json()["code"] == "extraction_disabled"


def test_extract_object_pulls_json_out_of_prose():
    text = 'Here you go:\n{"title": "Chemmeen", "authors": ["Thakazhi"]}\nHope that helps!'
    assert _extract_object(text) == {"title": "Chemmeen", "authors": ["Thakazhi"]}


def test_extract_object_returns_empty_on_garbage():
    assert _extract_object("no json") == {}
    assert _extract_object("{broken json]") == {}
    assert _extract_object('["a", "list"]') == {}


def test_clean_normalises_types_and_trims():
    raw = {
        "title": "  Chemmeen ",
        "authors": ["Thakazhi ", "", 42, " Anita"],
        "publisher": "",
        "description": "A love story on the Kerala coast.",
        "series_number": "3",
        "language": "Malayalam",
        "unexpected": "dropped",
    }
    cleaned = _clean(raw)
    assert cleaned == {
        "title": "Chemmeen",
        "authors": ["Thakazhi", "Anita"],
        "publisher": None,
        "description": "A love story on the Kerala coast.",
        "series_name": None,
        "series_number": 3,
        "language": "Malayalam",
        "form": None,
        "isbn": None,
    }


def test_clean_rejects_non_numeric_series_number():
    assert _clean({"series_number": "three"})["series_number"] is None
    assert _clean({"series_number": True})["series_number"] is None


def test_valid_isbn13_accepts_checksum_valid_and_normalises():
    # Real ISBN-13s (checksum-valid).
    assert valid_isbn13("978-3-16-148410-0") == "9783161484100"
    assert valid_isbn13("9789386906366") == "9789386906366"


def test_valid_isbn13_rejects_bad_input():
    assert valid_isbn13("9783161484101") is None  # bad checksum (last digit off)
    assert valid_isbn13("1234567890") is None  # 10 digits, not 13
    assert valid_isbn13("1234567890123") is None  # 13 digits but not 978/979
    assert valid_isbn13("not an isbn") is None
    assert valid_isbn13(None) is None


def test_clean_only_surfaces_a_valid_isbn():
    assert _clean({"isbn": "978-3-16-148410-0"})["isbn"] == "9783161484100"
    assert _clean({"isbn": "9783161484101"})["isbn"] is None  # misread digit dropped
    assert _clean({})["isbn"] is None


def test_allowed_image_url_is_scoped_to_our_covers_bucket():
    settings = Settings(supabase_url="https://proj.supabase.co")
    assert allowed_image_url(settings, f"{_BUCKET}/abc.jpg")
    assert allowed_image_url(settings, f"{_BUCKET}/covers/uuid.jpg?v=123")
    assert not allowed_image_url(settings, "https://evil.example/img.jpg")
    assert not allowed_image_url(
        settings, "https://proj.supabase.co/storage/v1/object/public/other/x.jpg"
    )
    # No supabase_url configured → nothing is allowed (fail closed).
    assert not allowed_image_url(Settings(supabase_url=""), f"{_BUCKET}/abc.jpg")


@pytest.mark.anyio
async def test_extract_from_covers_round_trip_with_fake_llm():
    """Full service path against a faked Anthropic response: images in, cleaned
    fields out."""
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        captured.update(json.loads(request.content))
        reply = (
            '{"title": "മയ്യഴിപ്പുഴയുടെ തീരങ്ങളിൽ", "authors": ["എം. മുകുന്ദൻ"], '
            '"publisher": "DC Books", "description": "ഒരു നോവൽ.", '
            '"series_name": null, "series_number": null, "language": "Malayalam"}'
        )
        return httpx.Response(200, json={"content": [{"type": "text", "text": reply}]})

    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as fake:
        fields = await extract_from_covers(
            settings,
            front_url=f"{_BUCKET}/front.jpg",
            back_url=f"{_BUCKET}/back.jpg",
            client=fake,
        )

    assert fields["title"] == "മയ്യഴിപ്പുഴയുടെ തീരങ്ങളിൽ"
    assert fields["authors"] == ["എം. മുകുന്ദൻ"]
    assert fields["publisher"] == "DC Books"
    assert fields["language"] == "Malayalam"
    # Both photos were sent as URL image blocks, front first.
    images = [b for b in captured["messages"][0]["content"] if b["type"] == "image"]
    assert [i["source"]["url"] for i in images] == [f"{_BUCKET}/front.jpg", f"{_BUCKET}/back.jpg"]
    assert captured["model"] == settings.extraction_model


def test_clean_gates_form_to_the_vocabulary():
    assert _clean({"form": "Novel"})["form"] == "Novel"
    assert _clean({"form": " Poetry "})["form"] == "Poetry"
    assert _clean({"form": "Romantic saga"})["form"] is None
    assert _clean({})["form"] is None


def test_cover_extract_out_surfaces_the_detected_type():
    """The response schema must carry `form` — the back cover's printed literary
    form (നോവൽ → Novel) is the Type the form prefills; a schema that drops it
    (as it silently did before) means the reader never gets the type."""
    from app.schemas.catalog import CoverExtractOut

    out = CoverExtractOut(**_clean({"title": "x", "form": "Novel"}))
    assert out.form == "Novel"
