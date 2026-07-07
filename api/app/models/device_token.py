"""DeviceToken model — an FCM registration token for one app install; online-only
transport state, not a syncable Layer-2 table."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class DeviceToken(Base):
    """An FCM registration token for one install of the app.

    Not a SyncableMixin table: it's device/transport state, online-only, owned
    by whoever is currently signed in on that device. A token is globally unique
    (FCM assigns it) — if the same device later signs in as a different user, the
    row's `user_id` is reassigned on re-register, so a stale token never pushes
    to the wrong account. Pruned when FCM reports it unregistered.
    """

    __tablename__ = "device_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    token: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    platform: Mapped[str | None] = mapped_column(String, default=None)  # ios | android

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
