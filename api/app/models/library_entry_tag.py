import uuid

from sqlalchemy import ForeignKey, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class LibraryEntryTag(SyncableMixin, Base):
    """Tag-to-entry assignment as its own syncable row (not a plain join
    table) — an assignment can be added/removed independently on separate
    devices, so it needs the same delete-wins/LWW conflict handling as
    everything else, which a bare many-to-many join table wouldn't carry."""

    __tablename__ = "library_entry_tags"

    library_entry_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("library_entries.id"), nullable=False
    )
    tag_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("personal_tags.id"), nullable=False)
