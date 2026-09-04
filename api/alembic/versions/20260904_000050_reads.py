"""reads — a read is a record, not a counter (CLAUDE.md rule 19).

Owner request, 29 Aug 2026: some readers read the same book more than once, and
each pass wants its own timer, its own log and a visible count. `library_entries`
has exactly one `start_date`, one `finish_date` and one `current_page`, so a
second pass has nowhere to live — this table gives each one its own row, and
`read_id` on sittings and notes says which pass they belong to.

Additive throughout: a new table plus two nullable columns. The entry keeps its
own columns as a mirror of the *current* read, so every existing reader of
`current_page` — the app's four progress surfaces, the timer, the Live Activity,
the public web pages — is untouched by this.

**The backfill lives here, not on the client.** One read per entry that shows
any evidence of reading, with its existing sittings and notes adopted into it.
Doing it on both sides would mint two ids for one pass and sync both; the same
division of labour migration 000037 used for borrowed books. Every row written
or touched draws a fresh `server_seq`, which is above any cursor a device can
already hold, so the rows arrive by the ordinary pull.

Revision ID: 000050
Revises: 000049
Create Date: 2026-08-29
Resequenced 4 Sep 2026: written when 000047 was head, but 000048
(rec_cache) and 000049 (works.merged_into_id) landed while it sat
uncommitted. The file's date prefix follows the sequence rather than the
create date, so `ls versions/` keeps telling the truth about the order.
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000050"
down_revision: str | None = "000049"
branch_labels = None
depends_on = None


BACKFILL_READS_SQL = """
INSERT INTO reads (
            id, user_id, library_entry_id, status,
            start_date, finish_date, current_page,
            created_at, updated_at, server_seq
        )
        SELECT
            gen_random_uuid(),
            e.user_id,
            e.id,
            CASE e.status WHEN 'read' THEN 'read'
                          WHEN 'stopped' THEN 'stopped'
                          ELSE 'reading' END,
            e.start_date,
            e.finish_date,
            e.current_page,
            e.created_at,
            now(),
            nextval('sync_seq')
        FROM library_entries e
        WHERE e.deleted_at IS NULL
          AND (
                e.start_date IS NOT NULL
             OR e.finish_date IS NOT NULL
             OR e.current_page IS NOT NULL
             OR e.status IN ('read', 'reading', 'stopped')
             OR EXISTS (SELECT 1 FROM reading_sessions s
                         WHERE s.library_entry_id = e.id AND s.deleted_at IS NULL)
          )
"""

#: Adopt an entry's existing sittings/notes into the one pass just written for
#: it. `{child}` is `reading_sessions` or `reading_notes`. Every touched row
#: draws a fresh `server_seq` so devices re-pull it and learn its `read_id`.
ADOPT_CHILDREN_SQL = """
    UPDATE {child} c
       SET read_id = r.id,
           server_seq = nextval('sync_seq'),
           updated_at = now()
      FROM reads r
     WHERE r.library_entry_id = c.library_entry_id
       AND c.read_id IS NULL
"""


def upgrade() -> None:
    op.create_table(
        "reads",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "library_entry_id",
            sa.Uuid(),
            sa.ForeignKey("library_entries.id"),
            nullable=False,
        ),
        sa.Column("status", sa.String(), nullable=False, server_default="reading"),
        sa.Column("start_date", sa.Date(), nullable=True),
        sa.Column("finish_date", sa.Date(), nullable=True),
        sa.Column("current_page", sa.Integer(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "server_seq",
            sa.BigInteger(),
            server_default=sa.text("nextval('sync_seq')"),
            nullable=False,
            unique=True,
        ),
    )
    op.create_index("ix_reads_user_id", "reads", ["user_id"])
    op.create_index("ix_reads_server_seq", "reads", ["server_seq"])
    op.create_index("ix_reads_user_seq", "reads", ["user_id", "server_seq"])
    # Rule 11 — deny by default. A new table without RLS is a security bug.
    op.execute("ALTER TABLE reads ENABLE ROW LEVEL SECURITY")

    op.add_column(
        "reading_sessions",
        sa.Column("read_id", sa.Uuid(), sa.ForeignKey("reads.id"), nullable=True),
    )
    op.add_column(
        "reading_notes",
        sa.Column("read_id", sa.Uuid(), sa.ForeignKey("reads.id"), nullable=True),
    )

    # --- backfill -----------------------------------------------------------
    # One read per entry with any evidence of reading: a date, a page, or a
    # sitting. A "to read" entry nobody has opened gets nothing — it has no
    # pass yet, and inventing one would claim a reading that never happened.
    #
    # `status` maps the entry's own status onto the pass: a finished book's
    # single read is finished, a book in progress has an open one. 'pending'
    # and 'wishlist' cannot reach here (no evidence), and anything unexpected
    # falls to 'reading', which is the recoverable direction — a pass wrongly
    # left open can be closed, while one wrongly closed loses the fact that it
    # was still going.
    # --- backfill -----------------------------------------------------------
    # One read per entry with any evidence of reading: a date, a page, or a
    # sitting. A "to read" entry nobody has opened gets nothing — it has no
    # pass yet, and inventing one would claim a reading that never happened.
    #
    # The statements live at module level so `test_reads_backfill.py` can run
    # the *real* SQL against seeded rows rather than a copy of it that would
    # only ever agree with itself (the 9 Aug 2026 fixture lesson).
    op.execute(BACKFILL_READS_SQL)
    for child in ("reading_sessions", "reading_notes"):
        op.execute(ADOPT_CHILDREN_SQL.format(child=child))


def downgrade() -> None:
    op.drop_column("reading_notes", "read_id")
    op.drop_column("reading_sessions", "read_id")
    op.drop_index("ix_reads_user_seq", table_name="reads")
    op.drop_index("ix_reads_server_seq", table_name="reads")
    op.drop_index("ix_reads_user_id", table_name="reads")
    op.drop_table("reads")
