"""repair: a wishlisted book that is out on loan to the reader is a borrowed one

Until 14 Oct 2026 the lending mirror reused a borrower's existing entry for the
book without changing it, so a book they had wishlisted — the ordinary path
since asks to borrow (wishlist → ask → lend) — stayed a *wish* while it sat in
their hands, and Home went on suggesting they borrow it. The mirror now flips
such an entry to a borrowed to-read book (lend_mirror_service); this puts right
the entries it already got wrong: wishlisted, with an open borrowed loan on that
same entry.

`server_seq` is bumped (UPDATEs never fire the column default — CLAUDE.md sync
lesson) so devices pull the correction. Data only; safe against the previous
image while the new one rolls.

Revision ID: 000059
Revises: 000058
"""

from collections.abc import Sequence

from alembic import op

revision: str = "000059"
down_revision: str | None = "000058"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE library_entries AS le
           SET status = 'pending',
               ownership = 'borrowed',
               updated_at = now(),
               server_seq = nextval('sync_seq')
         WHERE le.status = 'wishlist'
           AND le.deleted_at IS NULL
           AND EXISTS (
                 SELECT 1 FROM lending_records lr
                  WHERE lr.library_entry_id = le.id
                    AND lr.direction = 'borrowed'
                    AND lr.returned_date IS NULL
                    AND lr.deleted_at IS NULL
               )
        """
    )


def downgrade() -> None:
    # A repair of wrong data has nothing to restore.
    pass
