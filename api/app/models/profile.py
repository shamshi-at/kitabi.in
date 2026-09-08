"""Profile model — one row per Supabase auth user (the identity row), keyed by
auth.users.id; cross-user and online-only, so not a syncable Layer-2 table."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB
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

    # The reader's languages (list of names, e.g. ["Malayalam", "English"]) —
    # captured at onboarding, editable in profile; drives the add-book dropdown.
    preferred_languages: Mapped[list | None] = mapped_column(JSONB, default=None)

    # Public by default (owner decision, 9 Jul 2026): a reader is findable and
    # their profile viewable unless they opt out; library/reviews stay opt-in.
    profile_visible: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    library_visible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    reviews_visible_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    # Set by an admin (admin console) to lock a reader out of the API while
    # keeping their data. Null = active. Enforced in core.security.get_current_user.
    suspended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    # "Show promotions from Kitabi" (docs/promotions-plan.md §11). Default off
    # = promotions shown. Filtered in the serve query rather than hidden in the
    # app, so opting out stops the campaigns being *sent* to the device at all.
    promotions_opt_out: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, server_default="false"
    )

    # "Anyone with the link can see this window of my reading" — the gate on
    # /reader/<handle>/recap/<key> (8 Sep 2026). Its own flag rather than a
    # reuse of `library_visible`: that one defaults false, so gating on it
    # would leave the feature dead for almost everybody, and gating on nothing
    # would publish a reader's month because they tapped Share. Off until the
    # reader turns it on, and revocable from the profile screen — sharing a
    # picture and publishing a page are two different acts of consent.
    recaps_visible: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, server_default="false"
    )

    # Minutes east of UTC on the device that last talked to us. Windows in this
    # app are *local* calendar days (the app computes them in local time and
    # names them in the recap key), the database stores UTC, and without the
    # offset a late-night sitting lands in the wrong day on the shared page
    # while sitting in the right one on the card the reader sent. Deliberately
    # a fixed offset and not an IANA zone: it is exact for IST, wrong by an
    # hour at a window edge for readers who observe DST, and an IANA name
    # would cost a new dependency for that hour (rule 8).
    utc_offset_minutes: Mapped[int | None] = mapped_column(Integer, default=None)
