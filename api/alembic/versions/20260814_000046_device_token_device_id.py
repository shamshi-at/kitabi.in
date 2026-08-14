"""device_tokens.device_id — which install a push token belongs to.

Owner report (14 Aug 2026): starting a reading sitting put a "…is being timed
on your other device" banner on the device that had just started it. The
fan-out went to every token on the account, and the plan was for the
originating install to ignore its own event by comparing `device_id` in the
payload — which a *visible* notification never gets the chance to do, because
the OS renders it before any app code runs.

So the exclusion has to happen server-side, and that needs the server to know
which device each token belongs to. Nullable: tokens registered by older builds
have none and are treated as "some other device" — they keep receiving, which
is the safe direction, and they acquire an id the next time the app launches.

Revision ID: 000046
Revises: 000045
Create Date: 2026-08-14
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000046"
down_revision: str | None = "000045"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("device_tokens", sa.Column("device_id", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("device_tokens", "device_id")
