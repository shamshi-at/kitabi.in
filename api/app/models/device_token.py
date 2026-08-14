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

    `device_id` is the install's own id (the same one the sync engine uses), and
    it is what makes "push to my *other* devices" possible: a token is not a
    stable identity for an install (it rotates, and one install holds several
    over its life), so the only way to leave the originating device out of a
    fan-out is to know which device each token belongs to. Nullable because a
    token registered by an older build has none — such a row is treated as
    "some other device" and still receives, which is the safe direction.
    """

    __tablename__ = "device_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    token: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    platform: Mapped[str | None] = mapped_column(String, default=None)  # ios | android
    device_id: Mapped[str | None] = mapped_column(String, default=None)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
