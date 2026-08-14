"""Reading router — the live sitting, shared across one reader's devices.

Three endpoints and no more: a running timer is a single small fact about an
account. The *record* of the sitting is still a synced `reading_sessions` row
written by whichever device stops it; this only covers the window in between,
which offline-first sync cannot represent (see the model docstring).
"""

import uuid

from fastapi import APIRouter, BackgroundTasks, Response, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.reading import ActiveSessionIn, ActiveSessionOut
from app.services import active_session_service, push_service

router = APIRouter(prefix="/reading", tags=["reading"])


@router.get("/active", response_model=ActiveSessionOut | None)
async def read_active(user: CurrentUser, db: DbSession) -> ActiveSessionOut | None:
    """What is running on this account, if anything.

    The app calls this on foreground as the catch-all for a push it never
    received — a phone that was off, out of signal, or had notifications
    denied still converges the moment the reader looks at it.
    """
    row = await active_session_service.get(db, uuid.UUID(user["id"]))
    return None if row is None else ActiveSessionOut.model_validate(row)


@router.put("/active", response_model=ActiveSessionOut)
async def start_active(
    payload: ActiveSessionIn,
    user: CurrentUser,
    db: DbSession,
    background: BackgroundTasks,
) -> ActiveSessionOut:
    """Start or refresh the live sitting (idempotent on the account)."""
    user_id = uuid.UUID(user["id"])
    row = await active_session_service.start(db, user_id, payload)
    background.add_task(
        push_service.notify_reading_started,
        user_id,
        session_id=str(row.session_id),
        library_entry_id=str(row.library_entry_id),
        started_at=row.started_at.isoformat(),
        device_id=row.device_id,
    )
    return ActiveSessionOut.model_validate(row)


@router.delete("/active", status_code=status.HTTP_204_NO_CONTENT)
async def stop_active(
    user: CurrentUser,
    db: DbSession,
    background: BackgroundTasks,
    device_id: str | None = None,
) -> Response:
    """End the live sitting from any device.

    Idempotent: stopping something already stopped is a 204, not an error —
    both devices can race to stop the same sitting (the reader taps one, then
    picks up the other), and the loser must not see a failure for doing the
    thing that already happened.
    """
    user_id = uuid.UUID(user["id"])
    row = await active_session_service.clear(db, user_id)
    if row is not None:
        background.add_task(
            push_service.notify_reading_stopped,
            user_id,
            session_id=str(row.session_id),
            device_id=device_id,
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
