"""Add author_claims — "This is me" self-claims now queue for manual review.

Before this, `POST /catalog/authors/{id}/link` wrote `authors.linked_user_id`
outright: a self-declared, unverifiable edit applying instantly to shared
catalog data. It now writes a pending row here instead, and only an approval
touches `authors.linked_user_id` — so every other reader keeps seeing the old
value until a human agrees.

Existing links are left exactly as they are: they were made under the previous
first-to-claim-wins rule and re-litigating them is not this migration's job.

RLS enabled with zero policies (rule 11).

Revision ID: 000029
Revises: 000028
Create Date: 2026-07-22

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000029"
down_revision: str | None = "000028"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "author_claims",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("author_id", sa.Uuid(), sa.ForeignKey("authors.id"), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(), server_default="pending", nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decided_by_user_id", sa.Uuid(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        # One claim per reader per author; two readers may each claim the same
        # author, which is precisely what review exists to settle.
        sa.UniqueConstraint("author_id", "user_id", name="uq_author_claims_author_user"),
    )
    op.create_index("ix_author_claims_author_id", "author_claims", ["author_id"])
    op.create_index("ix_author_claims_user_id", "author_claims", ["user_id"])
    op.create_index("ix_author_claims_status", "author_claims", ["status"])
    op.execute("ALTER TABLE author_claims ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index("ix_author_claims_status", table_name="author_claims")
    op.drop_index("ix_author_claims_user_id", table_name="author_claims")
    op.drop_index("ix_author_claims_author_id", table_name="author_claims")
    op.drop_table("author_claims")
