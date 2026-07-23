"""Outbound email for the admin sign-in flows — with a dormant fallback.

Transport is deliberately undecided (owner call, rule 8: a provider is a new
credential/bill). Until SMTP is configured via env, `send` LOGS the message —
subject, recipient and body, including the OTP or link — to the server log, so
the flows work end to end today (grab the code from the Railway logs) and light
up for real the moment SMTP_HOST etc. are set. No new dependency: real sending
is stdlib smtplib.

Set to go live: SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, MAIL_FROM
(and ADMIN_BASE_URL so links point at the deployed host).
"""

import logging
import os
import smtplib
from email.message import EmailMessage

log = logging.getLogger("kitabi.admin.mail")


def base_url() -> str:
    """Public origin for links in emails. Defaults to the production host; set
    ADMIN_BASE_URL to override (e.g. http://localhost:8100 in dev)."""
    return os.getenv("ADMIN_BASE_URL", "https://admin.kitabi.in").rstrip("/")


def is_configured() -> bool:
    return bool(os.getenv("SMTP_HOST"))


def send(to: str, subject: str, body: str) -> None:
    """Deliver an email, or log it when no transport is configured. Never raises
    into the caller — a mail failure must not sink the flow that triggered it
    (the code/link still lives in the DB/log), so failures are logged and
    swallowed."""
    if not is_configured():
        log.warning("[MAIL dormant — no SMTP configured] to=%s subject=%r\n%s", to, subject, body)
        return
    try:
        msg = EmailMessage()
        msg["From"] = os.getenv("MAIL_FROM", "Kitabi Admin <admin@kitabi.in>")
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
    except Exception:  # noqa: BLE001
        log.exception("[MAIL send failed] to=%s subject=%r", to, subject)
