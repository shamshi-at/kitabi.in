"""One tap on a bookseller link — who, which book, which shop, from where.

The affiliate button (`services/buy_links.py`) has been on every book page
since August with nothing counting what it does: Amazon's own report says how
many orders a tag earned, never which of *our* pages sent them. This is that
missing half — which books readers go on to look at buying, from the app or
the website, through which shop — so trends are readable from our own data
(owner request, 5 Oct 2026).

Shaped like `PromotionEvent`, and for the same reasons: append-only, never
updated, never deleted, so it needs none of the sync engine's machinery —
no conflicts, no ordering, no `updated_at`.

- **App clicks** carry a device-generated `id`, so a retried batch collides
  on the primary key and is dropped rather than double-counted, and a
  `user_id` — the owner asked for *who*.
- **Website clicks** are anonymous by construction: no account, and nothing
  that identifies the visitor is stored — no IP, no user agent, no cookie.
  `user_id` is NULL and the `id` is made here.

`retailer` is a short key (`amazon`), not a display name and not an enum
column: there is one shop today and the owner expects more, and a new shop
must not need a migration (`buy_links.RETAILER_KEYS` is the vocabulary).

`work_id` is stored beside `edition_id` although the edition implies it. The
report this table exists for is "which *books*" — rule 17, a book is a Work —
and resolving it once at write time keeps every report query off a join.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

SURFACE_APP = "app"
SURFACE_WEB = "web"
SURFACES = (SURFACE_APP, SURFACE_WEB)


class BuyClick(Base):
    __tablename__ = "buy_clicks"
    __table_args__ = (
        # The report's three questions: what happened lately, which books,
        # and what one reader clicked.
        Index("ix_buy_clicks_occurred", "occurred_at"),
        Index("ix_buy_clicks_work", "work_id", "occurred_at"),
        Index("ix_buy_clicks_user", "user_id", "occurred_at"),
    )

    # Device-generated for the app (idempotent retries); made here for the web.
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    # NULL = a website visitor. Never a guess, never a device fingerprint.
    user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    work_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("works.id"), nullable=False)
    edition_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("editions.id"), default=None
    )
    retailer: Mapped[str] = mapped_column(String, nullable=False)
    surface: Mapped[str] = mapped_column(String, nullable=False)
    # Whether the link carried our tag when it was served — a click on an
    # untagged link is interest, but it is not a click that could have earned.
    affiliate: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # When it happened on the device (the app may report it much later).
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
