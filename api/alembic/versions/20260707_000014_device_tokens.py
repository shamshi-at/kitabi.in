"""FCM device tokens for push notifications.

One row per app install; token globally unique, user_id reassigned on
re-register. Online-only, not synced. RLS enabled, deny-by-default.

Revision ID: 000014
Revises: 000013
Create Date: 2026-07-07

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000014"
down_revision: str | None = "000013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "device_tokens",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token", sa.String(), nullable=False),
        sa.Column("platform", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("token", name="uq_device_tokens_token"),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.execute("ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index("ix_device_tokens_user_id", table_name="device_tokens")
    op.drop_table("device_tokens")
