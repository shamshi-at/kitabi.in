"""Author pen name + image, publisher logo — for the Kerala seed catalog.

Adds `pen_name`/`image_url` to authors and `logo_url` to publishers so the
seeded major Malayalam authors and publishers can carry their writing name,
portrait, and mark.

Revision ID: 000006
Revises: 000005
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000006"
down_revision: str | None = "000005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("authors", sa.Column("pen_name", sa.String(), nullable=True))
    op.add_column("authors", sa.Column("image_url", sa.String(), nullable=True))
    op.add_column("publishers", sa.Column("logo_url", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("publishers", "logo_url")
    op.drop_column("authors", "image_url")
    op.drop_column("authors", "pen_name")
