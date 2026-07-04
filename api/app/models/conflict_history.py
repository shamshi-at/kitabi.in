import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Uuid, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class ConflictHistory(Base):
    """One row per detected conflict (CLAUDE.md rule 6: conflicts write a
    history row, never resolve silently). Kitabi has no cross-user sharing
    in V1, so a conflict here means the SAME user's two devices disagreed —
    `winning_payload`/`discarded_payload` capture what each device had, for
    debugging and a future "sync issues" view. 30-day retention, same as
    rupee-diary's reference implementation."""

    __tablename__ = "conflict_history"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    entity: Mapped[str] = mapped_column(String, nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    rule: Mapped[str] = mapped_column(String, nullable=False)  # delete_wins | last_write_wins
    winning_payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    discarded_payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
