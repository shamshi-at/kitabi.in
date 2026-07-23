"""admin_auth_tokens + admin_users.must_change_password — the email sign-in flows.

Backs forgot-password OTP, passwordless magic links, and invite setup: one-time,
expiring, single-use tokens (only the hash stored). must_change_password forces
a real password after a forgot-password OTP sign-in (the OTP is a temp password).
RLS enabled, zero policies, like every table.

Revision ID: 000033
Revises: 000032
Create Date: 2026-07-24
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000033"
down_revision: str | None = "000032"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "admin_users",
        sa.Column(
            "must_change_password", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
    )
    op.create_table(
        "admin_auth_tokens",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("admin_id", sa.Uuid(), sa.ForeignKey("admin_users.id"), nullable=False),
        sa.Column("purpose", sa.String(), nullable=False),
        sa.Column("token_hash", sa.String(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index("ix_admin_auth_tokens_admin_id", "admin_auth_tokens", ["admin_id"])
    op.create_index("ix_admin_auth_tokens_purpose", "admin_auth_tokens", ["purpose"])
    op.create_index(
        "ix_admin_auth_tokens_token_hash", "admin_auth_tokens", ["token_hash"], unique=True
    )
    op.execute("ALTER TABLE admin_auth_tokens ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("admin_auth_tokens")
    op.drop_column("admin_users", "must_change_password")
