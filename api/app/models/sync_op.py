import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class SyncOp(Base):
    """Idempotency ledger — one row per attempted push op, keyed by the
    client-generated `op_id`. A retried batch (e.g. after a dropped
    connection) replays the same `op_id`s; this table is what makes that
    safe: a matching row means "already handled," not "do it again."""

    __tablename__ = "sync_ops"

    op_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    # Kitabi has no cross-user sharing (unlike rupee-diary's budgets), so the
    # conflict signal isn't "a different user touched this" — it's "a
    # different one of MY devices touched this." Generated once per install
    # and sent with every op.
    device_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    entity: Mapped[str] = mapped_column(String, nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    op_type: Mapped[str] = mapped_column(String, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False)
    applied_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (Index("ix_sync_ops_user_entity", "user_id", "entity", "entity_id"),)
