"""works.merged_into_id — a merged book's URL 301s instead of dying

Authors, publishers and series have carried this pointer since the console's
dedupe; Works never did, because only an admin could merge one. Readers can now
(POST /catalog/works/{id}/merge), and a book page is the one page on this site
that actually earns inbound links — so a merge that leaves the old URL 404ing
discards exactly the ranking it was supposed to consolidate.

Nullable with no default and no backfill: additive, and safe to run against the
previous version of the code, which is what serves traffic while the new image
rolls (CLAUDE.md — the container migrates on boot).

Revision ID: 000049
Revises: 000048
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000049"
down_revision: str | None = "000048"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("works", sa.Column("merged_into_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_works_merged_into_id_works", "works", "works", ["merged_into_id"], ["id"]
    )
    op.create_index(op.f("ix_works_merged_into_id"), "works", ["merged_into_id"])


def downgrade() -> None:
    op.drop_index(op.f("ix_works_merged_into_id"), table_name="works")
    op.drop_constraint("fk_works_merged_into_id_works", "works", type_="foreignkey")
    op.drop_column("works", "merged_into_id")
