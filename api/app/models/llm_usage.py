"""Per-reader, per-day metering for the two endpoints that spend real money —
`GET /recommendations` and `POST /catalog/cover-extract`, both of which call
Anthropic on every request.

Neither mixin applies: this is operational metering, not Layer-2 personal data
(nothing syncs to a device — no `server_seq`, no soft delete) and not Layer-1
catalog. Rows are disposable: deleting anything older than a few days loses
nothing, because a quota only ever reads today.

RLS enabled with zero policies like every other table (CLAUDE.md rule 11).
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Date,
    DateTime,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

# The metered features. Constants rather than free strings because the value is
# written into a column AND used to look up a per-feature cap — a typo would
# silently open a brand-new, uncapped bucket instead of failing.
FEATURE_RECOMMENDATIONS = "recommendations"
FEATURE_COVER_EXTRACT = "cover_extract"
LLM_FEATURES = (FEATURE_RECOMMENDATIONS, FEATURE_COVER_EXTRACT)


class LlmUsage(Base):
    """One row per (reader, feature, UTC day), holding that day's call count."""

    __tablename__ = "llm_usage"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    feature: Mapped[str] = mapped_column(String, nullable=False)
    # The **UTC** day (CLAUDE.md rule 5). A quota that rolled over at the
    # server's local midnight would drift with the deploy region and be
    # untestable; UTC is the one boundary both the API and a test agree on.
    day: Mapped[date] = mapped_column(Date, nullable=False)
    count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        # The upsert in `llm_quota.consume` conflicts on exactly this
        # constraint — it is what makes "increment and read back" a single
        # atomic statement rather than a read-then-write race.
        UniqueConstraint("user_id", "feature", "day", name="uq_llm_usage_user_feature_day"),
        # Serves the global circuit breaker's SUM over one day.
        Index("ix_llm_usage_day", "day"),
    )
