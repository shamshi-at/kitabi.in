"""Promotions router — what this reader should see, and what they did with it.

Two endpoints and no more: the admin console writes campaigns straight through
the shared ORM models, so there is no reader-facing write surface here at all.
"""

import uuid

from fastapi import APIRouter, Header, Request, Response, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.promotion import (
    PromotionEventsIn,
    PromotionEventsOut,
    PromotionsOut,
)
from app.services import promotion_service

router = APIRouter(prefix="/promotions", tags=["promotions"])


@router.get("", response_model=PromotionsOut)
async def list_promotions(
    request: Request,
    response: Response,
    user: CurrentUser,
    db: DbSession,
    x_platform: str | None = Header(default=None),
    x_app_version: str | None = Header(default=None),
) -> PromotionsOut:
    """Everything live and eligible for this reader, already resolved.

    Targeting runs here, never on the device: a campaign a reader doesn't match
    is never sent to their phone at all. `X-Platform` and `X-App-Version` (the
    app client sends both on every request) are the only two facts that come
    from the install rather than the database.
    """
    promotions = await promotion_service.resolve_for_reader(
        db,
        uuid.UUID(user["id"]),
        platform=(x_platform or "").lower() or None,
        app_version=x_app_version,
    )
    version = promotion_service.payload_version(promotions)
    etag = f'"{version}"'
    # The normal case is "nothing changed since the last poll" — answer it in a
    # few bytes rather than re-sending the payload every 30 minutes.
    if request.headers.get("if-none-match") == etag:
        response.status_code = status.HTTP_304_NOT_MODIFIED
        return PromotionsOut(version=version, promotions=[])
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return PromotionsOut(version=version, promotions=promotions)


@router.post("/events", response_model=PromotionEventsOut)
async def record_events(
    payload: PromotionEventsIn, user: CurrentUser, db: DbSession
) -> PromotionEventsOut:
    """Batched impressions/clicks/dismisses from the device's outbox.

    Always 200, even when nothing is stored: an event for a campaign that has
    since been deleted, or one already recorded, is dropped silently. Returning
    an error would make the app's outbox retry a batch that can never succeed.
    """
    accepted = await promotion_service.record_events(db, uuid.UUID(user["id"]), payload.events)
    return PromotionEventsOut(accepted=accepted)
