"""Buy-link click payloads — what the app reports from its outbox."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel


class BuyClickIn(BaseModel):
    """One tap. `id` is generated on the device so a retried batch collides on
    the primary key and is dropped instead of double-counted.

    `retailer` is deliberately a plain string, not a pattern: an app built
    before a shop was retired — or after one was added — must not have its
    whole batch refused with a 422 for one unfamiliar name. The service drops
    what it does not recognise.
    """

    id: uuid.UUID
    edition_id: uuid.UUID
    retailer: str
    affiliate: bool = False
    occurred_at: datetime


class BuyClicksIn(BaseModel):
    events: list[BuyClickIn]


class BuyClicksOut(BaseModel):
    accepted: int
