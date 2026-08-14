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


async def _push(
    target_id: uuid.UUID,
    title: str,
    body: str,
    data: dict[str, str],
    image: str | None = None,
    silent: bool = False,
    exclude_device_id: str | None = None,
) -> None:
    # Every entry point is supposed to be a no-op when push isn't configured
    # (rule 8), but only the actor-named ones checked — the self-pushes
    # (reading start/stop, notes) opened a DB session and looked up tokens on a
    # deployment with no Firebase credential at all. Guarding here covers all of
    # them, present and future.
    if not get_settings().push_enabled:
        return
    async with SessionLocal() as db:
        tokens = await device_service.tokens_for_user(
            db, target_id, exclude_device_id=exclude_device_id
        )
        if not tokens:
            return
        dead: list[str] = []
        async with httpx.AsyncClient(timeout=10) as client:
            for token in tokens:
                try:
                    result = await fcm_client.send(
                        client, token, title, body, data, image, silent=silent
                    )
                except Exception:  # noqa: BLE001 — a bad token must not sink the rest
                    result = fcm_client.ERROR
                if result == fcm_client.UNREGISTERED:
                    dead.append(token)
        await device_service.prune(db, dead)


async def _notify_from_actor(
    actor_id: uuid.UUID,
    target_id: uuid.UUID,
    title: str,
    body_suffix: str,
    data: dict[str, str],
    image: str | None = None,
) -> None:
    """Look up the actor's name and push `{name} {body_suffix}` to the target."""
    if not get_settings().push_enabled:
        return
    async with SessionLocal() as db:
        actor = await db.get(Profile, actor_id)
    name = _display_name(actor)
    await _push(target_id, title, f"{name} {body_suffix}", data, image)


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


async def notify_book_lent(
    actor_id: uuid.UUID, target_id: uuid.UUID, book_title: str, book_cover: str | None = None
) -> None:
    """Someone lent a book to the target (a connected reader)."""
    await _notify_from_actor(
        actor_id,
        target_id,
        title="A book's on its way to you",
        body_suffix=f"lent you “{book_title}” on Kitabi",
        data={"type": "lend_new"},
        image=book_cover,
    )


async def notify_book_returned(
    actor_id: uuid.UUID, target_id: uuid.UUID, book_title: str, book_cover: str | None = None
) -> None:
    """The lender marked a loan returned."""
    await _notify_from_actor(
        actor_id,
        target_id,
        title="Loan marked returned",
        body_suffix=f"marked “{book_title}” returned",
        data={"type": "lend_returned"},
        image=book_cover,
    )


async def notify_return_reminder(
    actor_id: uuid.UUID, target_id: uuid.UUID, book_title: str, book_cover: str | None = None
) -> None:
    """The lender nudges a connected borrower to return a book."""
    await _notify_from_actor(
        actor_id,
        target_id,
        title="A gentle nudge",
        body_suffix=f"would like “{book_title}” back",
        data={"type": "lend_reminder"},
        image=book_cover,
    )


async def notify_reading_started(
    user_id: uuid.UUID,
    *,
    session_id: str,
    library_entry_id: str,
    started_at: str,
    device_id: str | None,
    book_title: str | None = None,
) -> None:
    """Tell the reader's *other* devices that a sitting is running.

    This is the one push that goes to your own account rather than to someone
    else, so it carries no actor name. It is visible rather than silent: a
    second phone that was asleep when the timer started should still be able to
    say what is running and offer to stop it.

    Which is exactly why the originating install must be left out **here**. The
    first cut sent to every token and echoed `device_id` for the app to ignore
    its own event — but a visible notification is rendered by the OS before any
    app code runs, so the device that started the sitting got a banner telling
    it a sitting was running "on your other device" (owner report, 14 Aug 2026).
    The exclusion is by device rather than by token because one install holds
    several tokens over its life; `device_id` stays in the payload for the
    foreground case, where the app does see it.
    """
    title = "Reading in progress"
    body = (
        f"“{book_title}” is being timed on your other device"
        if book_title
        else ("A reading session is running on your other device")
    )
    await _push(
        user_id,
        title,
        body,
        {
            "type": "reading_started",
            "session_id": session_id,
            "library_entry_id": library_entry_id,
            "started_at": started_at,
            "device_id": device_id or "",
        },
        exclude_device_id=device_id,
    )


async def notify_reading_stopped(
    user_id: uuid.UUID,
    *,
    session_id: str,
    device_id: str | None,
) -> None:
    """Silent — the other device takes its ongoing notification down.

    Announcing this would be a banner about something the reader just did on a
    device in their hand. The device that stopped it is excluded anyway: it has
    already taken its own notification down, so the push would be pure wake-up.
    """
    await _push(
        user_id,
        "",
        "",
        {
            "type": "reading_stopped",
            "session_id": session_id,
            "device_id": device_id or "",
        },
        silent=True,
        exclude_device_id=device_id,
    )


async def notify_notes_changed(user_id: uuid.UUID) -> None:
    """Silent — "there is something new, pull now".

    Deliberately carries no content: the sync engine is the only thing that
    moves note bodies, and a push that tried to would be a second source of
    truth for private text.
    """
    await _push(user_id, "", "", {"type": "notes_changed"}, silent=True)
