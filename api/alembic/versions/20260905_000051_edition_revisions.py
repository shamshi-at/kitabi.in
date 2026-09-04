"""work_revisions.edition_id — the approval queue reaches printings too

`PATCH /catalog/works/{id}` has been moderated since the queue was built;
`PATCH /catalog/editions/{id}` never was, so any signed-in reader could
rewrite any printing's ISBN, page count, format, publisher and covers on the
shared catalogue with no approval and no record — the far more destructive
half of the same edit (owner report, 5 Sep 2026).

One queue rather than a second table: an edition edit is still an edit to the
book, its approver is still the Work's contributor, and the inbox, the admin
escalation and the decide path are all already written against this row.
`edition_id` null means the payload is a WorkUpdate (every existing row);
non-null means it is an EditionUpdate against that printing.

Nullable with no default and no backfill: additive, and safe to run against
the previous version of the code, which is what serves traffic while the new
image rolls (CLAUDE.md — the container migrates on boot).

Revision ID: 000051
Revises: 000050

Renumbered from 000050 on 5 Sep 2026: `reads` (a read is a record, not a
counter) landed on main under that number while this sat on a branch. Two
heads is not a merge conflict git can see — it is a boot that fails, and the
container migrates on boot, so it would restart-loop production.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000051"
down_revision: str | None = "000050"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("work_revisions", sa.Column("edition_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_work_revisions_edition_id_editions",
        "work_revisions",
        "editions",
        ["edition_id"],
        ["id"],
    )
    op.create_index(
        op.f("ix_work_revisions_edition_id"), "work_revisions", ["edition_id"]
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_work_revisions_edition_id"), table_name="work_revisions")
    op.drop_constraint(
        "fk_work_revisions_edition_id_editions", "work_revisions", type_="foreignkey"
    )
    op.drop_column("work_revisions", "edition_id")
