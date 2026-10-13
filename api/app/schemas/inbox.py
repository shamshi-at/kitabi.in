"""Pydantic shapes for the in-app inbox (the bell on Home)."""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class InboxActorOut(BaseModel):
    id: uuid.UUID
    name: str
    avatar_url: str | None = None


class InboxItemOut(BaseModel):
    id: uuid.UUID
    type: str
    title: str
    body: str
    # The push's own data — the app routes a tap with the same rule.
    data: dict[str, str] = {}
    image_url: str | None = None
    created_at: datetime
    read: bool
    actor: InboxActorOut | None = None


class InboxOut(BaseModel):
    unread: int
    items: list[InboxItemOut]


class UnreadOut(BaseModel):
    unread: int


class MarkReadIn(BaseModel):
    ids: list[uuid.UUID] = Field(min_length=1, max_length=200)
