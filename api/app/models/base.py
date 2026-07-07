"""Declarative base and the two column mixins every table builds on:
`SyncableMixin` for Layer-2 personal data (client-side UUIDs, `server_seq` pull
cursor, soft delete) and `CatalogMixin` for server-authoritative Layer-1 catalog."""

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Index, Uuid, func, text
from sqlalchemy.orm import DeclarativeBase, Mapped, declared_attr, mapped_column


class Base(DeclarativeBase):
    pass


class SyncableMixin:
    """Columns every syncable (Layer 2 / personal) table carries — CLAUDE.md
    rule 10. Layer 1 catalog tables are server-authoritative and do NOT use
    this mixin.

    - `id` is generated client-side (UUID v4) so offline-created records have
      stable identity before first sync; the server never assigns ids.
    - `server_seq` is the monotonic pull cursor (never timestamps). It draws
      from ONE global sequence (`sync_seq`) shared by all syncable tables so a
      single cursor orders changes across entities.
    - Soft deletes only: set `deleted_at`, never DELETE (rule 3).
    """

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    server_seq: Mapped[int] = mapped_column(
        BigInteger, server_default=text("nextval('sync_seq')"), index=True, unique=True
    )

    @declared_attr
    def user_id(cls) -> Mapped[uuid.UUID]:  # noqa: N805 — personal data belongs to one user
        return mapped_column(Uuid, index=True, nullable=False)

    @declared_attr.directive
    def __table_args__(cls):  # noqa: N805 — the sync-pull index (user_id, server_seq)
        return (Index(f"ix_{cls.__tablename__}_user_seq", "user_id", "server_seq"),)


class CatalogMixin:
    """Columns every Layer 1 (shared catalog) table carries.

    Server-authoritative, not user-owned — no `user_id`, no `server_seq`
    (there's nothing to sync-pull; the app fetches/searches these via API and
    caches them locally for offline reading, per CLAUDE.md rule 2). Soft
    deletes still apply (rule 3): a catalog entry can be superseded but is
    never hard-deleted, since personal library entries may reference it.
    """

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
