"""Outbound email for the admin sign-in flows.

Three transports, chosen by which env vars are set, in order:

1. Resend HTTP API — set RESEND_API_KEY (+ MAIL_FROM on your verified domain).
   Preferred: no outbound-SMTP-port worries on Railway, best deliverability.
2. SMTP — set SMTP_HOST/PORT/USER/PASSWORD (+ MAIL_FROM). stdlib smtplib.
3. Dormant — neither set: the message (OTP / link) is LOGGED to the server, so
   the flows still work end to end during setup (grab it from the Railway log).

`send` never raises into its caller — a mail failure must not sink the flow
that triggered it (the code/link still lives in the DB and the log).
"""

import logging
import os
import smtplib
from email.message import EmailMessage

log = logging.getLogger("kitabi.admin.mail")

RESEND_ENDPOINT = "https://api.resend.com/emails"
_DEFAULT_FROM = "Kitabi Admin <noreply@kitabi.in>"


def base_url() -> str:
    """Public origin for links in emails. Defaults to the production host; set
    ADMIN_BASE_URL to override (e.g. http://localhost:8100 in dev)."""
    return os.getenv("ADMIN_BASE_URL", "https://admin.kitabi.in").rstrip("/")


def _from() -> str:
    return os.getenv("MAIL_FROM", _DEFAULT_FROM)


def is_configured() -> bool:
    return bool(os.getenv("RESEND_API_KEY") or os.getenv("SMTP_HOST"))


def _send_resend(api_key: str, to: str, subject: str, body: str) -> None:
    import httpx  # available via the API's deps; lazy so import doesn't require it

    resp = httpx.post(
        RESEND_ENDPOINT,
        headers={"Authorization": f"Bearer {api_key}"},
        json={"from": _from(), "to": [to], "subject": subject, "text": body},
        timeout=15,
    )
    resp.raise_for_status()


def _send_smtp(to: str, subject: str, body: str) -> None:
    msg = EmailMessage()
    msg["From"] = _from()
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    host = os.environ["SMTP_HOST"]
    port = int(os.getenv("SMTP_PORT", "587"))
    with smtplib.SMTP(host, port, timeout=15) as s:
        s.starttls()
        user, password = os.getenv("SMTP_USER"), os.getenv("SMTP_PASSWORD")
        if user and password:
            s.login(user, password)
        s.send_message(msg)


def send(to: str, subject: str, body: str) -> None:
    api_key = os.getenv("RESEND_API_KEY")
    try:
        if api_key:
            _send_resend(api_key, to, subject, body)
        elif os.getenv("SMTP_HOST"):
            _send_smtp(to, subject, body)
        else:
            log.warning(
                "[MAIL dormant — no transport configured] to=%s subject=%r\n%s", to, subject, body
            )
    except Exception:  # noqa: BLE001
        log.exception("[MAIL send failed] to=%s subject=%r", to, subject)
