"""Service health and spend — the page that answers "is anything costing money
or quietly broken", without opening a Railway dashboard or a psql prompt.

Two endpoints in the API call Anthropic and therefore cost real money on every
request (`GET /recommendations`, `POST /catalog/cover-extract`). Both are
metered against `llm_usage` with a per-reader daily quota and a global daily
circuit breaker (CLAUDE.md: "any endpoint whose request costs money must be
metered before it ships"). The meter has existed since those endpoints shipped —
what has never existed is anywhere to *look* at it. A limit nobody can see is a
limit nobody notices hitting, and the day the breaker trips, recommendations
stop working for every reader with no signal anywhere in the console.

Everything on this page is read-only. Nothing here has a button, on purpose:
changing a quota is an environment-variable change and a deploy, which is a
different kind of act from clicking a tile.
"""

from datetime import UTC, datetime, timedelta

from app.core.config import get_settings
from app.models import FEATURE_COVER_EXTRACT, FEATURE_RECOMMENDATIONS
from app.services import llm_quota
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import func, select

from .. import assets, insights, mail, queries
from ..deps import DbSession, RequireEditor
from ..models_ref import LlmUsage, Profile, SyncOp
from ..templating import templates

router = APIRouter()

FEATURE_LABELS = {
    FEATURE_RECOMMENDATIONS: "Book recommendations",
    FEATURE_COVER_EXTRACT: "Reading a cover photo",
}

# How many days of spend the page charts.
SPEND_DAYS = 14


async def _spend(db: DbSession) -> dict:
    settings = get_settings()
    today = llm_quota.utc_day()
    axis = insights.day_axis(SPEND_DAYS, today)

    per_feature = {}
    for feature, label in FEATURE_LABELS.items():
        rows = (
            await db.execute(
                select(LlmUsage.day, func.sum(LlmUsage.count))
                .where(LlmUsage.feature == feature, LlmUsage.day >= axis[0])
                .group_by(LlmUsage.day)
            )
        ).all()
        buckets = {d: int(n or 0) for d, n in rows}
        values = [buckets.get(d, 0) for d in axis]
        per_feature[feature] = {
            "label": label,
            "today": buckets.get(today, 0),
            "window": sum(values),
            "values": values,
            "chart": insights.spark(values),
            "per_reader_cap": llm_quota.quota_for(settings, feature),
        }

    used_today = int(
        await db.scalar(
            select(func.coalesce(func.sum(LlmUsage.count), 0)).where(LlmUsage.day == today)
        )
        or 0
    )
    cap = int(settings.llm_daily_global_cap or 0)
    # The heaviest accounts today. This is the shape of "one script, fifty free
    # accounts" — the failure the global cap exists for — so it is worth being
    # able to see the names, not just the total.
    heavy = (
        await db.execute(
            select(Profile.id, Profile.full_name, Profile.email, func.sum(LlmUsage.count))
            .join(Profile, Profile.id == LlmUsage.user_id)
            .where(LlmUsage.day == today)
            .group_by(Profile.id, Profile.full_name, Profile.email)
            .order_by(func.sum(LlmUsage.count).desc())
            .limit(5)
        )
    ).all()
    return {
        "features": per_feature,
        "labels": [d.strftime("%-d %b") for d in axis],
        "used_today": used_today,
        "cap": cap,
        "cap_pct": round(100 * used_today / cap) if cap else 0,
        "tripped": bool(cap) and used_today >= cap,
        "configured": bool(settings.anthropic_api_key),
        "heavy": [
            {"id": pid, "name": full or email, "calls": int(n)} for pid, full, email, n in heavy
        ],
    }


@router.get("/system")
async def system(request: Request, admin: RequireEditor, db: DbSession) -> HTMLResponse:
    day_ago = datetime.now(UTC) - timedelta(hours=24)
    synced = int(
        await db.scalar(
            select(func.count()).select_from(SyncOp).where(SyncOp.applied_at >= day_ago)
        )
        or 0
    )
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "system.html",
        {
            "admin": admin,
            "active": "system",
            "badges": badges,
            "spend": await _spend(db),
            "sync_ops_24h": synced,
            "integrations": [
                # Each of these is "dormant until configured" by design — the
                # console must say which, or an operator reads silence as breakage.
                ("Email (invites, sign-in links)", mail.is_configured()),
                ("Image uploads from this console", assets.configured()),
                (
                    "AI features (recommendations, cover reading)",
                    bool(get_settings().anthropic_api_key),
                ),
            ],
        },
    )
