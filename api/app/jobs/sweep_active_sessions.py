"""Take down live reading sittings nobody will ever stop.

The running timer is one server row per account (`active_reading_sessions`),
and only a device's `DELETE /reading/active` removes it. A sitting the app
auto-stops in the background, or stops offline, retries that delete on the
next pull — which never comes if the phone is never opened again. Those rows
sat in the console's "Reading now" for a month (owner report, 12 Oct 2026),
and every other device on the account went on showing a clock.

The stop push goes to *every* device on the account, the one that held the
sitting included: if it ever wakes, it learns the account has let go and logs
its sitting as overdue (`active_session_sync.dart`).
"""

import logging
from datetime import UTC, datetime

from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_SWEEP_ACTIVE_SESSIONS, advisory_lock
from app.services import active_session_service, push_service

logger = logging.getLogger(__name__)


async def sweep_active_sessions() -> None:
    async with SessionLocal() as session:
        async with advisory_lock(session, LOCK_SWEEP_ACTIVE_SESSIONS) as acquired:
            if not acquired:
                return
            swept = await active_session_service.sweep_stale(session, datetime.now(UTC))
    for row in swept:
        logger.info(
            "sweep_active_sessions: cleared sitting %s (user %s, started %s)",
            row.session_id,
            row.user_id,
            row.started_at.isoformat(),
        )
        try:
            await push_service.notify_reading_stopped(
                row.user_id, session_id=str(row.session_id), device_id=None
            )
        except Exception:  # noqa: BLE001 — a push must never fail the sweep
            logger.exception("sweep_active_sessions: stop push failed for %s", row.user_id)
