"""One-shot flash messages across a POST-redirect-GET, carried in a short cookie.

The value is base64-encoded because a raw cookie is latin-1 only — an em-dash or
a Malayalam author name in a flash message would otherwise 500 the response at
the point it's set (found live, 23 Jul 2026). Encoding makes the transport
indifferent to the message's script.
"""

import base64

from fastapi import Request
from fastapi.responses import Response

_COOKIE = "admin_flash"


def set_flash(resp: Response, kind: str, text: str) -> None:
    payload = base64.urlsafe_b64encode(f"{kind}|{text}".encode()).decode()
    resp.set_cookie(_COOKIE, payload, max_age=10, httponly=True, samesite="strict", path="/")


def pop_flash(request: Request) -> dict | None:
    raw = request.cookies.get(_COOKIE)
    if not raw:
        return None
    try:
        decoded = base64.urlsafe_b64decode(raw.encode()).decode()
    except Exception:  # noqa: BLE001 — a malformed flash cookie is just ignored
        return None
    kind, _, text = decoded.partition("|")
    return {"kind": kind or "ok", "text": text}
