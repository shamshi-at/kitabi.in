"""Backfill works.aggregate_rating from the live ratings table.

The column has existed since the first catalog migration and NOTHING ever wrote
it — five orderings (`_more_by_author`, home rails, translation-group averages)
and every public WorkCard read permanent NULL, so "Top rated" could sort a grid
it couldn't caption. The writer now exists (`review_service.
refresh_aggregate_rating`, called for every applied rating sync op); this is the
half that reaches rows rated before the writer was born.

Data-only, no schema change, idempotent, and safe to run against the previous
code version (which merely keeps reading the column, now non-NULL where rated).
Both statements are needed: the first fills rated works, the second nulls any
work whose every rating has since been soft-deleted — impossible today (the
column was never written), but the pair makes re-running this against any
future state converge on the truth instead of assuming the present one.

Rounds to 2 decimal places exactly like `rating_summary`, so the page's figure
and the card's can never disagree visibly.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "000042"
down_revision: str | None = "000041"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE works
        SET aggregate_rating = sub.avg_value
        FROM (
            SELECT work_id, round(avg(value)::numeric, 2)::float8 AS avg_value
            FROM ratings
            WHERE deleted_at IS NULL
            GROUP BY work_id
        ) sub
        WHERE works.id = sub.work_id
          AND works.aggregate_rating IS DISTINCT FROM sub.avg_value
        """
    )
    op.execute(
        """
        UPDATE works
        SET aggregate_rating = NULL
        WHERE aggregate_rating IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM ratings
            WHERE ratings.work_id = works.id AND ratings.deleted_at IS NULL
          )
        """
    )


def downgrade() -> None:
    # Restoring permanent NULL would be restoring a bug; the column simply
    # goes back to being ignored by older code. Nothing to undo.
    pass
