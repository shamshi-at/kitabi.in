"""Minimal FCM HTTP v1 sender — no firebase-admin dependency.

Mints a service-account JWT with PyJWT (already a dep), exchanges it for an
OAuth access token (cached until it nears expiry), and POSTs to the FCM v1
`messages:send` endpoint with httpx (already a dep). Deliberately tiny: a
personal app pushes a handful of messages, not millions.

Dormant unless `settings.firebase_credentials` is set (rule 8 — opt-in): every
entry point checks `settings.push_enabled` first, so with no credential nothing
here runs and no external call is made.
"""

import json
import time
from typing import Any

import httpx
import jwt

from app.core.config import get_settings

_TOKEN_URI = "https://oauth2.googleapis.com/token"
_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_FCM_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# Result of one send: delivered, token should be pruned, or a transient failure.
SENT = "sent"
UNREGISTERED = "unregistered"
ERROR = "error"

_creds: dict[str, Any] | None = None
_token_cache: dict[str, Any] = {"value": None, "exp": 0.0}


def _load_creds() -> dict[str, Any]:
    global _creds
    if _creds is None:
        _creds = json.loads(get_settings().firebase_credentials)
    return _creds


async def _access_token(client: httpx.AsyncClient) -> str:
    now = time.time()
    if _token_cache["value"] and _token_cache["exp"] - 60 > now:
        return _token_cache["value"]
    creds = _load_creds()
    assertion = jwt.encode(
        {
            "iss": creds["client_email"],
            "sub": creds["client_email"],
            "aud": _TOKEN_URI,
            "scope": _SCOPE,
            "iat": int(now),
            "exp": int(now) + 3600,
        },
        creds["private_key"],
        algorithm="RS256",
    )
    resp = await client.post(
        _TOKEN_URI,
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        },
    )
    resp.raise_for_status()
    payload = resp.json()
    _token_cache["value"] = payload["access_token"]
    _token_cache["exp"] = now + payload.get("expires_in", 3600)
    return _token_cache["value"]


async def send(
    client: httpx.AsyncClient,
    token: str,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
    image: str | None = None,
) -> str:
    """Send one message. Returns SENT / UNREGISTERED (prune it) / ERROR.

    `image` (e.g. a book cover URL) rides along as a rich-notification image:
    Android shows it big-picture automatically; iOS needs the app's Notification
    Service Extension, which `mutable-content` + `fcm_options.image` trigger.
    """
    creds = _load_creds()
    access = await _access_token(client)
    notification: dict[str, Any] = {"title": title, "body": body}
    apns: dict[str, Any] = {"headers": {"apns-priority": "10"}}
    if image:
        notification["image"] = image
        apns["headers"]["apns-push-type"] = "alert"
        apns["payload"] = {"aps": {"mutable-content": 1}}
        apns["fcm_options"] = {"image": image}
    message: dict[str, Any] = {
        "token": token,
        "notification": notification,
        "android": {"priority": "high"},
        "apns": apns,
    }
    if data:
        message["data"] = data
    resp = await client.post(
        _FCM_URL.format(project_id=creds["project_id"]),
        headers={"Authorization": f"Bearer {access}"},
        json={"message": message},
    )
    if resp.status_code == 200:
        return SENT
    # A dead token comes back as 404 UNREGISTERED (or 400 with that status).
    if resp.status_code in (400, 404):
        detail = resp.text
        if "UNREGISTERED" in detail or "INVALID_ARGUMENT" in detail:
            return UNREGISTERED
    return ERROR
