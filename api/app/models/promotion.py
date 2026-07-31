"""Promotion models — the in-app banner/card system (docs/promotions-plan.md).

Operator-owned content, not reader data: a promotion is written in the admin
console and served to whoever matches its targeting. Not `SyncableMixin` (it
isn't the reader's to sync) and not `CatalogMixin` either (it isn't a book) —
the column set is spelled out here so nobody reads it as either one.

Three tables:

- `promotions`      the campaign: surface, schedule, targeting, frequency
- `promotion_contents`  the copy, one row per language (null = the default)
- `promotion_events`    append-only impression/click/dismiss facts

**Targeting and content variants are deliberately separate mechanisms.**
Targeting decides who is eligible; variants decide which words they see. One
"Onam sale" campaign therefore carries both the Malayalam and the English copy,
shares one schedule and one metrics bucket, and can't drift out of step the way
two parallel campaigns would.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

# JSONB on Postgres, plain JSON on SQLite so the model still imports/creates in
# a non-Postgres test harness (same escape hatch profile.preferred_languages
# would need if it were ever exercised off-Postgres).
_Json = JSONB().with_variant(JSON(), "sqlite")

KIND_BANNER = "banner"
KIND_CARD = "card"
KINDS = (KIND_BANNER, KIND_CARD)

CARD_BOOK = "book"
CARD_IMAGE = "image"
CARD_TEXT = "text"
CARD_STYLES = (CARD_BOOK, CARD_IMAGE, CARD_TEXT)

PLACEMENT_HOME_TOP = "home_top"
PLACEMENT_HOME_STREAM = "home_stream"
PLACEMENTS = (PLACEMENT_HOME_TOP, PLACEMENT_HOME_STREAM)

# `status` is the operator's *intent*, not the campaign's current life stage.
# "Scheduled", "live" and "ended" are derived from the dates every time they're
# needed (promotion_service.effective_state) rather than stored — otherwise
# something has to run on a timer to flip rows, and the day it doesn't run, a
# finished campaign is still live. Nothing here needs a scheduler.
STATUS_DRAFT = "draft"
STATUS_PUBLISHED = "published"
STATUS_PAUSED = "paused"
STATUSES = (STATUS_DRAFT, STATUS_PUBLISHED, STATUS_PAUSED)

# Derived, never stored — what the console shows and what the serve query means.
STATE_DRAFT = "draft"
STATE_SCHEDULED = "scheduled"
STATE_LIVE = "live"
STATE_PAUSED = "paused"
STATE_ENDED = "ended"

ACTION_NONE = "none"
ACTION_DEEP_LINK = "deep_link"
ACTION_EXTERNAL_URL = "external_url"
ACTIONS = (ACTION_NONE, ACTION_DEEP_LINK, ACTION_EXTERNAL_URL)

EVENT_IMPRESSION = "impression"
EVENT_CLICK = "click"
EVENT_DISMISS = "dismiss"
EVENT_KINDS = (EVENT_IMPRESSION, EVENT_CLICK, EVENT_DISMISS)


class Promotion(Base):
    """One campaign. Its copy lives in `promotion_contents`, its results in
    `promotion_events`."""

    __tablename__ = "promotions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)

    name: Mapped[str] = mapped_column(String, nullable=False)  # internal, never shown to readers
    kind: Mapped[str] = mapped_column(String, nullable=False, default=KIND_BANNER)
    card_style: Mapped[str | None] = mapped_column(String, default=None)
    placement: Mapped[str] = mapped_column(String, nullable=False, default=PLACEMENT_HOME_TOP)
    status: Mapped[str] = mapped_column(String, nullable=False, default=STATUS_DRAFT, index=True)

    # Null = "From Kitabi"; set = "Sponsored · {sponsor}". The reader-facing
    # label is derived from this field in the app, never typed by the author —
    # a disclosure you can forget to write is a disclosure that gets forgotten.
    sponsor: Mapped[str | None] = mapped_column(String, default=None)

    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    # "Runs until I stop it." A null `ends_at` alone can't tell a deliberate
    # open-ended campaign from one whose end date nobody has set yet, and the
    # console has to treat those differently — the first is ready to publish,
    # the second is the campaign that gets forgotten.
    open_ended: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, server_default="false"
    )

    # See promotion_service for the full key list. Absent key = don't filter.
    targeting: Mapped[dict] = mapped_column(_Json, nullable=False, default=dict)
    # max_impressions | min_hours_between | dismissible | redisplay_after_days
    frequency: Mapped[dict] = mapped_column(_Json, nullable=False, default=dict)

    # The campaign's *subject* — the one catalog thing it is about. At most one
    # of these is set; the server resolves whichever it is into a title and an
    # image for the card (promotion_service._subjects_for).
    #
    # Deliberately separate from the destination: `action_value` lives on the
    # per-language copy, so it can't carry the campaign's artwork, and "which
    # book is this about" is not the same question as "where does a tap go".
    work_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("works.id"), default=None)
    edition_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("editions.id"), default=None
    )
    author_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("authors.id"), default=None
    )
    publisher_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("publishers.id"), default=None
    )

    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)  # admin_users.id
    updated_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    # Soft delete only (rule 3) — events reference this row forever.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)


class PromotionContent(Base):
    """The copy for one language. `language` null is the default variant, used
    for any reader with no matching language.

    A promotion with no default and no variant the reader matches is skipped
    entirely rather than shown in a language they didn't ask for.
    """

    __tablename__ = "promotion_contents"
    __table_args__ = (
        # A named language may appear once per promotion. The null-language
        # default needs its own partial unique index — Postgres treats NULLs as
        # distinct, so a plain UNIQUE(promotion_id, language) would happily
        # allow five default rows.
        Index(
            "uq_promotion_contents_lang",
            "promotion_id",
            "language",
            unique=True,
            postgresql_where="language IS NOT NULL",
            sqlite_where="language IS NOT NULL",
        ),
        Index(
            "uq_promotion_contents_default",
            "promotion_id",
            unique=True,
            postgresql_where="language IS NULL",
            sqlite_where="language IS NULL",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    promotion_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("promotions.id"), nullable=False, index=True
    )
    # A full language name from app/lib/core/languages.dart ('Malayalam'), to
    # match what profiles.preferred_languages stores. Null = default variant.
    language: Mapped[str | None] = mapped_column(String, default=None)

    headline: Mapped[str] = mapped_column(String, nullable=False)
    body: Mapped[str | None] = mapped_column(String, default=None)
    cta_label: Mapped[str | None] = mapped_column(String, default=None)
    image_url: Mapped[str | None] = mapped_column(String, default=None)

    action_type: Mapped[str] = mapped_column(String, nullable=False, default=ACTION_NONE)
    action_value: Mapped[str | None] = mapped_column(String, default=None)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class PromotionEvent(Base):
    """One impression, click or dismiss. Append-only; never updated, never
    deleted.

    `id` is generated on the *device*, so a retried batch collides on the
    primary key and is discarded rather than double-counted — the same
    idempotency trick the sync engine's op UUIDs use. This is why promo events
    don't need (and must not use) the sync queue: no updates, no deletes, no
    conflicts, nothing to order.
    """

    __tablename__ = "promotion_events"
    __table_args__ = (
        # The serve query's two hot lookups: "has this reader dismissed it" and
        # "how many times have they seen it".
        Index("ix_promotion_events_reader", "user_id", "promotion_id", "kind"),
        Index("ix_promotion_events_promo_kind", "promotion_id", "kind"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    promotion_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("promotions.id"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    kind: Mapped[str] = mapped_column(String, nullable=False)
    # Which variant they actually saw — so "did the Malayalam copy work?" is
    # answerable. Null for the default variant.
    language: Mapped[str | None] = mapped_column(String, default=None)

    # When it happened on the device (may be well before it was reported).
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
