"""profiles.recaps_visible + profiles.utc_offset_minutes — shared reading recaps

A share card is a picture; a recap link is a page on kitabi.in that anyone who
has the URL can read (owner request, 8 Sep 2026 — "if we share a month card
with link, others can see what all books he read in that month"). Those are two
different acts of consent, so the page gets its own flag rather than riding one
that already exists: `library_visible` defaults false, so gating on it would
leave the feature dead for almost every reader, and gating on nothing would
publish a reader's month because they tapped Share. Default false, revocable
from the profile screen — rule 16's own pattern.

`utc_offset_minutes` is what lets the server cut a window on the reader's
calendar rather than UTC's. The app computes and *names* its windows in local
time (`recapKeyFor`), the database stores UTC, and without the offset a
late-night sitting falls in a different day on the shared page than on the card
that linked to it. A fixed offset rather than an IANA zone deliberately: exact
for IST, an hour out at a window edge under DST, and an IANA name would cost a
new dependency for that hour (rule 8).

Both additive, both with server defaults, no backfill — safe to run against the
previous version of the code, which is what serves traffic while the new image
rolls (CLAUDE.md — the container migrates on boot).

Revision ID: 000052
Revises: 000051
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000052"
down_revision: str | None = "000051"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column(
            "recaps_visible", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
    )
    op.add_column("profiles", sa.Column("utc_offset_minutes", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("profiles", "utc_offset_minutes")
    op.drop_column("profiles", "recaps_visible")
