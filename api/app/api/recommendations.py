"""Recommendations router: the opt-in LLM-reasoned book recs (dormant unless an
Anthropic key is configured)."""

import uuid

from fastapi import APIRouter

from app.api.catalog import _summary
from app.api.deps import CurrentUser, DbSession
from app.core.config import get_settings
from app.schemas.catalog import RecommendationOut, RecommendationsOut
from app.services import recommendation_service

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


@router.get("", response_model=RecommendationsOut)
async def get_recommendations(user: CurrentUser, db: DbSession) -> RecommendationsOut:
    """S11 — reasoned picks from the reader's own ratings. Requires auth (it's
    personal). `enabled` is False (with no picks) when the feature is dormant."""
    settings = get_settings()
    picks = await recommendation_service.recommend(db, uuid.UUID(user["id"]))
    return RecommendationsOut(
        enabled=settings.recommendations_enabled,
        picks=[RecommendationOut(work=_summary(work), why=why) for work, why in picks],
    )
