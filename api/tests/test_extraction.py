"""Cover-photo extraction: the gate (dormant without a key), URL restriction,
and the service's parsing/cleaning — the LLM call itself is faked via
httpx.MockTransport, mirroring the recommendations tests."""

import httpx
import pytest

from app.core.config import Settings, get_settings
from app.services import extraction_service
from app.services.extraction_service import (
    _BLURB_SYSTEM,
    _clean,
    _extract_object,
    allowed_image_url,
    extract_blurb,
    extract_from_covers,
    extract_identity,
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


def test_valid_isbn13_converts_an_isbn10_off_an_older_cover():
    """Pre-2007 printings — most of a second-hand shelf — print only the
    10-digit form. Rejecting those dropped a field we could read perfectly."""
    assert valid_isbn13("8126403454") == "9788126403455"
    assert valid_isbn13("81-264-0345-4") == "9788126403455"
    assert valid_isbn13("316148410X") == "9783161484100"  # X check character


def test_valid_isbn13_rejects_bad_input():
    assert valid_isbn13("9783161484101") is None  # bad checksum (last digit off)
    assert valid_isbn13("8126403455") is None  # ISBN-10 shape, bad checksum
    assert valid_isbn13("1234567890") is None  # 10 digits, fails the ISBN-10 checksum
    assert valid_isbn13("1234567890123") is None  # 13 digits but not 978/979
    assert valid_isbn13("not an isbn") is None
    assert valid_isbn13(None) is None


def test_valid_isbn13_still_refuses_a_non_bookland_ean():
    """OCR of a cover can land on some other product's barcode. 5901234123457
    is a checksum-valid EAN-13 and not a book — the 978/979 gate is what stops
    it prefilling a catalogue entry."""
    assert valid_isbn13("5901234123457") is None


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
    bodies: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        bodies.append(json.loads(request.content))
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
    assert fields["description"] == "ഒരു നോവൽ."
    # Identified by its prompt rather than by arrival order — the two calls are
    # concurrent, so which lands first is not something to assert on.
    identity = next(b for b in bodies if b["system"] != _BLURB_SYSTEM)
    # Both photos were sent as URL image blocks, front first.
    images = [b for b in identity["messages"][0]["content"] if b["type"] == "image"]
    assert [i["source"]["url"] for i in images] == [f"{_BUCKET}/front.jpg", f"{_BUCKET}/back.jpg"]
    assert identity["model"] == settings.extraction_model


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


# --- the split: identity fast, blurb behind it -----------------------------


def _fake_transport(calls: list[dict], reply_for):
    """Records every request body and answers with `reply_for(body)` text."""

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        body = json.loads(request.content)
        calls.append(body)
        return httpx.Response(200, json={"content": [{"type": "text", "text": reply_for(body)}]})

    return httpx.MockTransport(handler)


@pytest.mark.anyio
async def test_identity_call_never_carries_the_blurb():
    """The whole point of the split: the fast half must not spend its output
    budget on a 150-word Malayalam paragraph. Even when the model volunteers a
    description anyway, the identity result drops it — the blurb call owns that
    field, and a half-filled one would race the real answer into the form."""
    calls: list[dict] = []
    reply = (
        '{"title": "മയ്യഴിപ്പുഴയുടെ തീരങ്ങളിൽ", "authors": ["എം. മുകുന്ദൻ"], '
        '"publisher": "DC Books", "description": "ഒരു നീണ്ട നോവൽ.", "isbn": null}'
    )
    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with httpx.AsyncClient(transport=_fake_transport(calls, lambda _: reply)) as fake:
        fields = await extract_identity(
            settings,
            front_url=f"{_BUCKET}/front.jpg",
            back_url=f"{_BUCKET}/back.jpg",
            client=fake,
        )

    assert fields["title"] == "മയ്യഴിപ്പുഴയുടെ തീരങ്ങളിൽ"
    assert fields["publisher"] == "DC Books"
    assert "description" not in fields
    # Both photos go in — the title is on the front, the ISBN on the back.
    images = [b for b in calls[0]["messages"][0]["content"] if b["type"] == "image"]
    assert [i["source"]["url"] for i in images] == [f"{_BUCKET}/front.jpg", f"{_BUCKET}/back.jpg"]
    # The blurb's budget is not handed to the fast call.
    assert calls[0]["max_tokens"] < 2048


@pytest.mark.anyio
async def test_blurb_call_sends_only_the_back_cover():
    calls: list[dict] = []
    reply = '{"description": "കടലിന്റെ കഥ."}'
    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with httpx.AsyncClient(transport=_fake_transport(calls, lambda _: reply)) as fake:
        fields = await extract_blurb(settings, back_url=f"{_BUCKET}/back.jpg", client=fake)

    assert fields == {"description": "കടലിന്റെ കഥ."}
    images = [b for b in calls[0]["messages"][0]["content"] if b["type"] == "image"]
    assert [i["source"]["url"] for i in images] == [f"{_BUCKET}/back.jpg"]


@pytest.mark.anyio
async def test_blurb_falls_back_to_the_front_when_that_is_the_only_photo():
    """It would be cheaper to skip the call outright without a back cover, but
    a front-only read can already return a description today and must keep
    doing so — the split is for latency, not thrift."""
    calls: list[dict] = []
    reply = '{"description": "കടലിന്റെ കഥ."}'
    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with httpx.AsyncClient(transport=_fake_transport(calls, lambda _: reply)) as fake:
        fields = await extract_blurb(
            settings, back_url=None, front_url=f"{_BUCKET}/front.jpg", client=fake
        )

    assert fields == {"description": "കടലിന്റെ കഥ."}
    images = [b for b in calls[0]["messages"][0]["content"] if b["type"] == "image"]
    assert [i["source"]["url"] for i in images] == [f"{_BUCKET}/front.jpg"]


@pytest.mark.anyio
async def test_extract_from_covers_merges_both_halves():
    """An app build older than the split sends no `part` and must still get one
    complete answer — now assembled from two concurrent calls."""
    calls: list[dict] = []

    def reply_for(body: dict) -> str:
        if body["system"] == _BLURB_SYSTEM:
            return '{"description": "കടലിന്റെ കഥ."}'
        return '{"title": "ചെമ്മീൻ", "authors": ["തകഴി"], "form": "Novel"}'

    settings = Settings(anthropic_api_key="test-key", supabase_url="https://proj.supabase.co")
    async with httpx.AsyncClient(transport=_fake_transport(calls, reply_for)) as fake:
        fields = await extract_from_covers(
            settings,
            front_url=f"{_BUCKET}/front.jpg",
            back_url=f"{_BUCKET}/back.jpg",
            client=fake,
        )

    assert len(calls) == 2
    assert fields["title"] == "ചെമ്മീൻ"
    assert fields["authors"] == ["തകഴി"]
    assert fields["form"] == "Novel"
    assert fields["description"] == "കടലിന്റെ കഥ."


@pytest.mark.anyio
async def test_each_part_spends_its_own_quota_unit(client, monkeypatch):
    """The split is two paid calls, so it is two units — a latency win, not a
    way to read twice as many covers on one day's quota. Pinned because the
    opposite (metering one half only) would ship an unmetered paid call, which
    CLAUDE.md forbids outright."""
    from app.services import llm_quota

    enabled = get_settings().model_copy(
        # `_BUCKET` has to be the bucket these settings name, or the router
        # rejects the URLs before it ever reaches the meter.
        update={"anthropic_api_key": "test-key", "supabase_url": "https://proj.supabase.co"}
    )
    monkeypatch.setattr("app.api.catalog.get_settings", lambda: enabled)

    consumed: list[str] = []

    async def _record(db, user_id, feature, **kwargs):
        consumed.append(feature)
        return len(consumed)

    monkeypatch.setattr(llm_quota, "consume", _record)

    async def _fake_blurb(settings, **kwargs):
        return {"description": "കടലിന്റെ കഥ."}

    async def _fake_identity(settings, **kwargs):
        return {"title": "ചെമ്മീൻ", "authors": [], "publisher": None}

    monkeypatch.setattr(extraction_service, "extract_blurb", _fake_blurb)
    monkeypatch.setattr(extraction_service, "extract_identity", _fake_identity)

    for part in ("identity", "description"):
        resp = await client.post(
            "/catalog/cover-extract",
            json={"front_url": f"{_BUCKET}/f.jpg", "back_url": f"{_BUCKET}/b.jpg", "part": part},
        )
        assert resp.status_code == 200, resp.text

    assert len(consumed) == 2
