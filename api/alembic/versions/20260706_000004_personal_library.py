"""Add personal library tables (Layer 2) + sync infrastructure.

library_entries, ratings, reviews, personal_tags, library_entry_tags,
lending_records, activity_log_entries — all SyncableMixin (client UUID,
user_id, soft delete, shared sync_seq). Plus sync_ops (push idempotency
ledger) and conflict_history (delete-wins/LWW audit log), neither of which
is itself synced to the client. RLS enabled with zero policies on every
table (rule 11): only the API touches these directly.

Revision ID: 000004
Revises: 000003
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from alembic import op

revision: str = "000004"
down_revision: str | None = "000003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _syncable_columns() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "server_seq",
            sa.BigInteger(),
            server_default=sa.text("nextval('sync_seq')"),
            nullable=False,
            unique=True,
        ),
    ]


def _enable_rls(*tables: str) -> None:
    for table in tables:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")


def upgrade() -> None:
    op.create_table(
        "library_entries",
        *_syncable_columns(),
        sa.Column("edition_id", sa.Uuid(), sa.ForeignKey("editions.id"), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("start_date", sa.Date(), nullable=True),
        sa.Column("finish_date", sa.Date(), nullable=True),
        sa.Column("current_page", sa.Integer(), nullable=True),
        sa.Column("is_favorite", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("notes", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_library_entries_user_seq", "library_entries", ["user_id", "server_seq"])
    op.create_index("ix_library_entries_edition_id", "library_entries", ["edition_id"])

    op.create_table(
        "ratings",
        *_syncable_columns(),
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), nullable=False),
        sa.Column("value", sa.Integer(), nullable=False),
        sa.CheckConstraint("value BETWEEN 1 AND 5", name="ck_ratings_value_range"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ratings_user_seq", "ratings", ["user_id", "server_seq"])
    op.create_index("ix_ratings_work_id", "ratings", ["work_id"])

    op.create_table(
        "reviews",
        *_syncable_columns(),
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), nullable=False),
        sa.Column("body", sa.String(), nullable=False),
        sa.Column("visible", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_reviews_user_seq", "reviews", ["user_id", "server_seq"])
    op.create_index("ix_reviews_work_id", "reviews", ["work_id"])

    op.create_table(
        "personal_tags",
        *_syncable_columns(),
        sa.Column("name", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_personal_tags_user_seq", "personal_tags", ["user_id", "server_seq"])

    op.create_table(
        "library_entry_tags",
        *_syncable_columns(),
        sa.Column(
            "library_entry_id", sa.Uuid(), sa.ForeignKey("library_entries.id"), nullable=False
        ),
        sa.Column("tag_id", sa.Uuid(), sa.ForeignKey("personal_tags.id"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_library_entry_tags_user_seq", "library_entry_tags", ["user_id", "server_seq"]
    )

    op.create_table(
        "lending_records",
        *_syncable_columns(),
        sa.Column(
            "library_entry_id", sa.Uuid(), sa.ForeignKey("library_entries.id"), nullable=False
        ),
        sa.Column("borrower_name", sa.String(), nullable=False),
        sa.Column("borrower_user_id", sa.Uuid(), nullable=True),
        sa.Column("lent_date", sa.Date(), nullable=False),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column("returned_date", sa.Date(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_lending_records_user_seq", "lending_records", ["user_id", "server_seq"])

    op.create_table(
        "activity_log_entries",
        *_syncable_columns(),
        sa.Column("event_type", sa.String(), nullable=False),
        sa.Column("entity_type", sa.String(), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("payload", JSONB(), nullable=False, server_default="{}"),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_activity_log_entries_user_seq", "activity_log_entries", ["user_id", "server_seq"]
    )

    op.create_table(
        "sync_ops",
        sa.Column("op_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False),
        sa.Column("entity", sa.String(), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("op_type", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column(
            "applied_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("op_id"),
    )
    op.create_index("ix_sync_ops_user_id", "sync_ops", ["user_id"])
    op.create_index("ix_sync_ops_user_entity", "sync_ops", ["user_id", "entity", "entity_id"])

    op.create_table(
        "conflict_history",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("entity", sa.String(), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("rule", sa.String(), nullable=False),
        sa.Column("winning_payload", JSONB(), nullable=False),
        sa.Column("discarded_payload", JSONB(), nullable=False),
        sa.Column(
            "occurred_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_conflict_history_user_id", "conflict_history", ["user_id"])

    _enable_rls(
        "library_entries",
        "ratings",
        "reviews",
        "personal_tags",
        "library_entry_tags",
        "lending_records",
        "activity_log_entries",
        "sync_ops",
        "conflict_history",
    )


def downgrade() -> None:
    op.drop_table("conflict_history")
    op.drop_table("sync_ops")
    op.drop_table("activity_log_entries")
    op.drop_table("lending_records")
    op.drop_table("library_entry_tags")
    op.drop_table("personal_tags")
    op.drop_table("reviews")
    op.drop_table("ratings")
    op.drop_table("library_entries")
