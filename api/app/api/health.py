from fastapi import APIRouter, Response
from sqlalchemy import text

from app.api.deps import DbSession
from app.core.config import get_settings

router = APIRouter(tags=["health"])


@router.get("/healthz")
async def healthz(response: Response, db: DbSession) -> dict:
    """Liveness + DB reachability. A DB-broken instance must fail health
    checks, or rolling deploys keep it in rotation serving 500s."""
    db_ok = True
    try:
        await db.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 — any DB failure means unhealthy
        db_ok = False
        response.status_code = 503
    return {
        "status": "ok" if db_ok else "degraded",
        "db": db_ok,
        "version": get_settings().app_version,
    }
