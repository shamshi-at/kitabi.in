"""promotions.author_id / publisher_id — a campaign can feature any of the three.

Until now a campaign could only link a Work, so a book cover was the only image
the server could resolve. Featuring an author or a publisher needs its own link
(owner request, 31 Jul 2026): the *destination* is per-language copy, so it
can't carry the campaign's artwork.

Revision ID: 000036
Revises: 000035
Create Date: 2026-07-31
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000036"
down_revision: str | None = "000035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "promotions", sa.Column("author_id", sa.Uuid(), sa.ForeignKey("authors.id"), nullable=True)
    )
    op.add_column(
        "promotions",
        sa.Column("publisher_id", sa.Uuid(), sa.ForeignKey("publishers.id"), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("promotions", "publisher_id")
    op.drop_column("promotions", "author_id")
