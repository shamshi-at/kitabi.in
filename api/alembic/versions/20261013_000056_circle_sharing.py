"""Circle sharing — profiles.circle_share_* + library_entries.circle_hidden

"Your circle is reading" (docs/circle-reading-mockups.html, owner go-ahead
13 Oct 2026): a reader's accepted connections may see what they read, how they
rated it and which books they own — each only if the reader said so.

Three switches rather than one because they are three different disclosures:
being seen reading, having your stars attributed to you (until now a rating
only ever fed an anonymous average, so attributing it needs a fresh yes), and
inviting borrow requests. All default false — a rating given privately must
not become attributed without consent — and the app asks at the moment the
feature has something to show.

`circle_hidden` is "keep this one to myself": a per-copy override that beats
every switch. It lives on the library entry, so it syncs like the rest of the
entry and can be set offline.

All additive with server defaults, no backfill — safe against the previous
version of the code while the new image rolls (the container migrates on boot).

Revision ID: 000056
Revises: 000055
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000056"
down_revision: str | None = "000055"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_PROFILE_FLAGS = ("circle_share_reading", "circle_share_ratings", "circle_share_owned")


def upgrade() -> None:
    for name in _PROFILE_FLAGS:
        op.add_column(
            "profiles",
            sa.Column(name, sa.Boolean(), nullable=False, server_default=sa.text("false")),
        )
    op.add_column(
        "library_entries",
        sa.Column("circle_hidden", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )


def downgrade() -> None:
    op.drop_column("library_entries", "circle_hidden")
    for name in reversed(_PROFILE_FLAGS):
        op.drop_column("profiles", name)
