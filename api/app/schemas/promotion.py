"""Promotion request/response schemas — the reader-facing shapes only. The
admin console writes the tables through the ORM directly (it shares the API's
models), so there is deliberately no create/update schema here."""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.models.promotion import EVENT_KINDS


class PromotionOut(BaseModel):
    """One promotion, already resolved for the caller: their language variant
    picked, targeting applied, frequency honoured. The app renders this as-is —
    it holds no targeting rules, because a device is never told about a
    campaign it isn't in."""

    id: uuid.UUID
    kind: str  # banner | card
    card_style: str | None = None
    placement: str
    # Null = "From Kitabi"; set = "Sponsored · {sponsor}". The app derives the
    # label from this rather than trusting a typed-in one.
    sponsor: str | None = None
    language: str | None = None

    headline: str
    body: str | None = None
    cta_label: str | None = None
    image_url: str | None = None

    action_type: str  # none | deep_link | external_url
    action_value: str | None = None
    work_id: uuid.UUID | None = None
    edition_id: uuid.UUID | None = None

    dismissible: bool = True
    priority: int = 5
    # So a finished campaign disappears on the device without a network call.
    expires_at: datetime | None = None


class PromotionsOut(BaseModel):
    """`version` is the payload hash, also sent as the ETag — the app's poll is
    normally a 304."""

    version: str
    promotions: list[PromotionOut]


class PromotionEventIn(BaseModel):
    """One engagement fact. `id` is generated on the device so a retried batch
    collides on the primary key and is dropped instead of double-counted."""

    id: uuid.UUID
    promotion_id: uuid.UUID
    kind: str = Field(pattern="^(" + "|".join(EVENT_KINDS) + ")$")
    language: str | None = None
    occurred_at: datetime


class PromotionEventsIn(BaseModel):
    events: list[PromotionEventIn]


class PromotionEventsOut(BaseModel):
    accepted: int
