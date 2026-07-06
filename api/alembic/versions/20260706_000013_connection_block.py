"""Blockable connections — a terminal state a denied request can't reopen from.

A denied request can be re-sent (reopens to pending); a *blocked* one can't.
`blocked_by` records who blocked, so only they can unblock.

Revision ID: 000013
Revises: 000012
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000013"
down_revision: str | None = "000012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("connections", sa.Column("blocked_by", sa.Uuid(), nullable=True))


def downgrade() -> None:
    op.drop_column("connections", "blocked_by")
