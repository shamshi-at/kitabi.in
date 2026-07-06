import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Profile(Base):
    """One row per Supabase auth user.

    Not a SyncableMixin table: this *is* the user, keyed directly by their
    auth.users.id rather than a client-generated id, and it isn't part of the
    offline sync queue — the app talks to it directly once online (rule 1
    applies to Layer 2 entities the user owns, not to their own identity row).

    Visibility columns are the dormant community switchboard (feature-map.md
    rule 4): wired now, default false, until Layer 4 goes live.
    """

    __tablename__ = "profiles"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String, nullable=False)
    full_name: Mapped[str | None] = mapped_column(String, default=None)
    avatar_url: Mapped[str | None] = mapped_column(String, default=None)

    # Optional, unique public handle — how others find this reader to lend to
    # (feature-map.md: real user reference for lending). Stored lowercased so a
    # plain unique constraint is case-insensitive. Null until the user sets one.
    username: Mapped[str | None] = mapped_column(String, unique=True, default=None)

    profile_visible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    library_visible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    reviews_visible_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
