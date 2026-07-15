"""authors.linked_user_id — self-service "This is me" author↔reader linking.

Nullable FK-shaped column (no formal FK constraint, matching the rest of the
codebase's "id refs profiles.id, checked in the app layer" convention — see
created_by_user_id on this same table). No claim/approval workflow: scoped to
an invited friend circle for now (docs/author-identity-and-moderation-plan.md).

Revision ID: 000024
Revises: 000023
Create Date: 2026-07-14
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000024"
down_revision: str | None = "000023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("authors", sa.Column("linked_user_id", sa.Uuid(), nullable=True))
    op.create_index("ix_authors_linked_user_id", "authors", ["linked_user_id"])


def downgrade() -> None:
    op.drop_index("ix_authors_linked_user_id", table_name="authors")
    op.drop_column("authors", "linked_user_id")
