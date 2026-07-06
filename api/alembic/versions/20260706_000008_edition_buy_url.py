"""Edition buy_url ([WIRED] external ecommerce link).

Adds `buy_url` to editions — a per-edition external buy link (ISBN → an
ecommerce product page). Dormant: the app surfaces a "Buy" affordance only when
this is populated, so shipping the column now means no rewrite when real store
links are wired later.

Revision ID: 000008
Revises: 000007
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000008"
down_revision: str | None = "000007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("editions", sa.Column("buy_url", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("editions", "buy_url")
