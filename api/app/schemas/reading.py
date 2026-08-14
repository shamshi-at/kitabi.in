"""Schemas for the live reading sitting — the one running right now.

Deliberately small: the *record* of a sitting is a synced `reading_sessions`
row and keeps its own shape. This is only what a second device needs to render
and stop the timer.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ActiveSessionIn(BaseModel):
    """Start (or refresh) the live sitting for this account."""

    #: Minted client-side at start, so the finished row carries the same id
    #: whichever device writes it (rule 4: the server never assigns ids).
    session_id: uuid.UUID
    library_entry_id: uuid.UUID
    started_at: datetime
    page_start: int | None = None
    confirmed_at: datetime | None = None
    #: The install starting it — echoed in the push so it can skip its own event.
    device_id: str | None = None


class ActiveSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    session_id: uuid.UUID
    library_entry_id: uuid.UUID
    started_at: datetime
    page_start: int | None
    confirmed_at: datetime | None
    device_id: str | None
    updated_at: datetime
