import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Uuid
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class ActivityLogEntry(SyncableMixin, Base):
    """[WIRED] — your own activity log, logged from day one so it's
    structurally identical to the future community feed (feature-map.md
    rule 15: "flip it public later"). Written as a side effect of other
    mutations (services/activity_service.py), never created directly by the
    client — the client only ever pulls these."""

    __tablename__ = "activity_log_entries"

    event_type: Mapped[str] = mapped_column(String, nullable=False)
    entity_type: Mapped[str] = mapped_column(String, nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
