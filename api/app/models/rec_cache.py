"""A reader's last generated recommendations, so re-opening the screen is free.

The picks are a pure function of what feeds the prompt — the reader's rated
books and what they own — and none of that changes between two visits to the
screen. Before this cache, every visit that passed the free gates burned a
fresh Anthropic call for an answer that could not differ (owner request,
2 Sep 2026): the quota bounded the bill, but most of what it was bounding was
re-computation of the same result.

Like `llm_usage`, neither mixin applies: server-side operational data, not
Layer-2 personal data (nothing syncs — no `server_seq`, no soft delete) and
not Layer-1 catalog. One row per reader, overwritten in place; deleting the
table loses nothing but one regeneration per reader.

RLS enabled with zero policies like every other table (CLAUDE.md rule 11).
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Uuid
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class RecCache(Base):
    """The last non-empty result of `recommendation_service.recommend`."""

    __tablename__ = "rec_cache"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    # Hash of exactly what fed the prompt (rated pairs, owned work ids, limit,
    # model) — when it matches, regeneration could only reproduce the answer.
    fingerprint: Mapped[str] = mapped_column(String, nullable=False)
    # [{"work_id": "<uuid>", "why": "<sentence>"}], in pick order. Work ids,
    # not embedded work data: the works are re-read on every serve, so a book
    # deleted or retitled since generation is never shown stale.
    picks: Mapped[list] = mapped_column(JSONB, nullable=False)
    # When the LLM actually ran — the TTL reads this, so a fingerprint-stable
    # reader still gets fresh picks once the catalogue has had time to grow.
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
