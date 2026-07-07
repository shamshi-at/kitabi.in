"""High-level push notifications — the bridge between app events and FCM.

Each `notify_*` is self-contained: it opens its own DB session, so it's safe to
hand to FastAPI `BackgroundTasks` (which run after the request's session has
closed). All are no-ops unless push is configured (`settings.push_enabled`), so
callers can enqueue them unconditionally.
"""

import uuid

import httpx

from app.core.config import get_settings
from app.core.db import SessionLocal
from app.models.profile import Profile
from app.services import device_service, fcm_client


def _display_name(p: Profile | None) -> str:
    if p is None:
        return "Someone"
    if p.full_name and p.full_name.strip():
        return p.full_name.strip()
    if p.username:
        return f"@{p.username}"
    return "Someone"


async def _push(target_id: uuid.UUID, title: str, body: str, data: dict[str, str]) -> None:
    async with SessionLocal() as db:
        tokens = await device_service.tokens_for_user(db, target_id)
        if not tokens:
            return
        dead: list[str] = []
        async with httpx.AsyncClient(timeout=10) as client:
            for token in tokens:
                try:
                    result = await fcm_client.send(client, token, title, body, data)
                except Exception:  # noqa: BLE001 — a bad token must not sink the rest
                    result = fcm_client.ERROR
                if result == fcm_client.UNREGISTERED:
                    dead.append(token)
        await device_service.prune(db, dead)


async def _notify_from_actor(
    actor_id: uuid.UUID, target_id: uuid.UUID, title: str, body_suffix: str, data: dict[str, str]
) -> None:
    """Look up the actor's name and push `{name} {body_suffix}` to the target."""
    if not get_settings().push_enabled:
        return
    async with SessionLocal() as db:
        actor = await db.get(Profile, actor_id)
    name = _display_name(actor)
    await _push(target_id, title, f"{name} {body_suffix}", data)


async def notify_connection_request(actor_id: uuid.UUID, target_id: uuid.UUID) -> None:
    await _notify_from_actor(
        actor_id,
        target_id,
        title="New connection request",
        body_suffix="wants to connect on Kitabi",
        data={"type": "connection_request"},
    )


async def notify_connection_accepted(actor_id: uuid.UUID, target_id: uuid.UUID) -> None:
    await _notify_from_actor(
        actor_id,
        target_id,
        title="Connection accepted",
        body_suffix="accepted your connection on Kitabi",
        data={"type": "connection_accepted"},
    )


async def notify_book_lent(actor_id: uuid.UUID, target_id: uuid.UUID, book_title: str) -> None:
    """Someone lent a book to the target (a connected reader)."""
    await _notify_from_actor(
        actor_id,
        target_id,
        title="A book's on its way to you",
        body_suffix=f"lent you “{book_title}” on Kitabi",
        data={"type": "lend_new"},
    )


async def notify_book_returned(actor_id: uuid.UUID, target_id: uuid.UUID, book_title: str) -> None:
    """The lender marked a loan returned."""
    await _notify_from_actor(
        actor_id,
        target_id,
        title="Loan marked returned",
        body_suffix=f"marked “{book_title}” returned",
        data={"type": "lend_returned"},
    )


async def notify_return_reminder(
    actor_id: uuid.UUID, target_id: uuid.UUID, book_title: str
) -> None:
    """The lender nudges a connected borrower to return a book."""
    await _notify_from_actor(
        actor_id,
        target_id,
        title="A gentle nudge",
        body_suffix=f"would like “{book_title}” back",
        data={"type": "lend_reminder"},
    )
