"""Move series membership from Edition to Work, and give Series a real identity.

Two changes, one idea: **a position in a series is a property of the story.**

`editions.series_id` / `editions.series_number` made it a property of a
printing. A work with two editions therefore had two answers to "which book in
the series is this?", which the public series page papered over with
`min(series_number) GROUP BY work_id`. Worse, it had no answer at all for the
question this catalogue actually asks — a Malayalam translation is its own
Work, so a translated series either duplicated the whole ordering under a second
series row or lost it. On the Work, one position is shared by every translation
of that story (services/catalog_service inherits it when translations link), and
the series page groups by position instead of listing the same book once per
language.

The backfill takes the LOWEST number across a work's editions — the same rule
the read path already applied, so no book changes position. Editions keep their
columns for now: this migration ships ahead of the app release that stops
sending them, and the API keeps serving `EditionOut.series` from the work so
installs in the field don't lose the series line. They come out in a later
migration, once nothing writes them.

Series also gains what Author and Publisher already have: the cross-script
search columns (a Malayalam series name was invisible to a Latin query — there
was nothing to match against), the merge pointer that lets a duplicate fold into
a canonical row while its URL keeps redirecting, and a primary language. Free
text has been minting series rows for months; this is what the existing merge
tooling needs to clean them up.

`name_translit` / `name_fold` are left NULL here rather than computed. Doing it
in SQL would need a copy of the transliteration tables, and a migration that
imports application code is welded to a moving target (see 000038/000041). The
ORM hooks fill them on the next write, and `jobs/backfill_series_search` sweeps
the rest — the same shape as the slug backfill.

Revision ID: 000043
Revises: 000042
Create Date: 2026-08-13
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000043"
down_revision: str | None = "000042"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("works", sa.Column("series_id", sa.Uuid(), nullable=True))
    op.add_column("works", sa.Column("series_number", sa.Integer(), nullable=True))
    op.create_foreign_key("fk_works_series", "works", "series", ["series_id"], ["id"])
    op.create_index("ix_works_series_id", "works", ["series_id"])

    op.add_column("series", sa.Column("merged_into_id", sa.Uuid(), nullable=True))
    op.add_column("series", sa.Column("name_translit", sa.String(), nullable=True))
    op.add_column("series", sa.Column("name_fold", sa.String(), nullable=True))
    op.add_column("series", sa.Column("primary_language", sa.String(), nullable=True))
    op.add_column("series", sa.Column("description", sa.String(), nullable=True))
    op.add_column("series", sa.Column("external_source", sa.String(), nullable=True))
    op.add_column("series", sa.Column("external_id", sa.String(), nullable=True))
    op.create_foreign_key("fk_series_merged_into", "series", "series", ["merged_into_id"], ["id"])
    op.create_index("ix_series_merged_into_id", "series", ["merged_into_id"])
    op.create_index("ix_series_external_id", "series", ["external_id"])

    # Carry every existing membership across. One row per work: the series of
    # its earliest-numbered edition in a series, and the lowest number found —
    # which is what the read path already showed.
    op.execute(
        """
        UPDATE works w
        SET series_id = src.series_id,
            series_number = src.series_number
        FROM (
            SELECT DISTINCT ON (e.work_id)
                   e.work_id,
                   e.series_id,
                   MIN(e.series_number) OVER (PARTITION BY e.work_id) AS series_number
            FROM editions e
            WHERE e.series_id IS NOT NULL AND e.deleted_at IS NULL
            ORDER BY e.work_id, e.series_number NULLS LAST, e.created_at
        ) AS src
        WHERE w.id = src.work_id AND w.series_id IS NULL
        """
    )


def downgrade() -> None:
    op.drop_index("ix_series_external_id", table_name="series")
    op.drop_index("ix_series_merged_into_id", table_name="series")
    op.drop_constraint("fk_series_merged_into", "series", type_="foreignkey")
    for column in (
        "external_id",
        "external_source",
        "description",
        "primary_language",
        "name_fold",
        "name_translit",
        "merged_into_id",
    ):
        op.drop_column("series", column)

    op.drop_index("ix_works_series_id", table_name="works")
    op.drop_constraint("fk_works_series", "works", type_="foreignkey")
    op.drop_column("works", "series_number")
    op.drop_column("works", "series_id")
