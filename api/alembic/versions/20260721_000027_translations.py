"""Translation structure (Area 8 mockups, 21 Jul 2026): translator credits and
the original↔translation direction.

- `work_translators` — who translated a Work. Translators are Author rows (they
  get the same catalog pages; names are doors), joined via their own association
  table rather than a `role` column on work_authors so the existing authors
  relationship keeps its simple write path.
- `works.original_work_id` — nullable self-FK marking *which* Work in a
  translation group is this one's original. `translation_group_id` stays the
  undirected cross-navigation set; this adds the direction the book page needs
  for "Translation of …" and the picker's "Original" stamp. Null on originals
  and on legacy flat-linked groups.

Revision ID: 000027
Revises: 000026
Create Date: 2026-07-21
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000027"
down_revision: str | None = "000026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "work_translators",
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), primary_key=True),
        sa.Column("author_id", sa.Uuid(), sa.ForeignKey("authors.id"), primary_key=True),
    )
    # Deny-by-default like every other catalog table (CLAUDE.md rule 11):
    # RLS on, zero policies — only the API's service-role connection reads it.
    op.execute("ALTER TABLE work_translators ENABLE ROW LEVEL SECURITY")

    op.add_column("works", sa.Column("original_work_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_works_original_work_id", "works", "works", ["original_work_id"], ["id"]
    )
    op.create_index("ix_works_original_work_id", "works", ["original_work_id"])


def downgrade() -> None:
    op.drop_index("ix_works_original_work_id", table_name="works")
    op.drop_constraint("fk_works_original_work_id", "works", type_="foreignkey")
    op.drop_column("works", "original_work_id")
    op.drop_table("work_translators")
