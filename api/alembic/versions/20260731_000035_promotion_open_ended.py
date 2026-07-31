"""promotions.open_ended — "runs until I stop it", stored as a deliberate choice.

`ends_at IS NULL` alone can't tell "the operator chose open-ended" from "nobody
has set an end date yet". The console needs the difference: the first is ready
to publish, the second is a campaign about to be forgotten (owner report,
31 Jul 2026 — the checklist demanded an end date while the box was ticked).

Revision ID: 000035
Revises: 000034
Create Date: 2026-07-31
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000035"
down_revision: str | None = "000034"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "promotions",
        sa.Column("open_ended", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )


def downgrade() -> None:
    op.drop_column("promotions", "open_ended")
