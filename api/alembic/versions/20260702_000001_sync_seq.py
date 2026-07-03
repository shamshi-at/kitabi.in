"""Global sync sequence.

One sequence shared by ALL syncable (Layer 2) tables so a single pull cursor
orders changes across entities (see app/models/base.py SyncableMixin).

Revision ID: 000001
Revises:
Create Date: 2026-07-02

"""

from collections.abc import Sequence

from alembic import op

revision: str = "000001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE SEQUENCE IF NOT EXISTS sync_seq")


def downgrade() -> None:
    op.execute("DROP SEQUENCE IF EXISTS sync_seq")
