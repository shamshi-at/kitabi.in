"""The mail sender picks its transport from env, and never raises into callers.

Real delivery isn't exercised here (that needs live Resend/SMTP creds); these
lock in the selection logic and the swallow-don't-raise contract the sign-in
flows depend on.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from console import mail


def test_dormant_when_nothing_configured(monkeypatch, caplog):
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    monkeypatch.delenv("SMTP_HOST", raising=False)
    assert mail.is_configured() is False
    with caplog.at_level("WARNING"):
        mail.send("a@b.com", "Subj", "the code is 123456")
    # The body (with the code) is logged so the flow still works during setup.
    assert "123456" in caplog.text


def test_resend_is_preferred_and_gets_the_right_request(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_key")
    monkeypatch.setenv("MAIL_FROM", "Kitabi <noreply@kitabi.in>")
    captured = {}

    def fake_post(url, headers=None, json=None, timeout=None):
        captured.update(url=url, headers=headers, json=json)

        class _R:
            def raise_for_status(self):
                return None

        return _R()

    import httpx

    monkeypatch.setattr(httpx, "post", fake_post)
    assert mail.is_configured() is True
    mail.send("dest@example.com", "Hello", "body text")

    assert captured["url"] == mail.RESEND_ENDPOINT
    assert captured["headers"]["Authorization"] == "Bearer re_test_key"
    assert captured["json"]["from"] == "Kitabi <noreply@kitabi.in>"
    assert captured["json"]["to"] == ["dest@example.com"]
    assert captured["json"]["subject"] == "Hello"


def test_send_swallows_transport_errors(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_key")

    def boom(*a, **k):
        raise RuntimeError("network down")

    import httpx

    monkeypatch.setattr(httpx, "post", boom)
    # Must not raise — the OTP/link still lives in the DB; a mail failure is logged.
    mail.send("dest@example.com", "Hello", "body")
