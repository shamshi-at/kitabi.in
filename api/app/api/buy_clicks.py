"""Buy-link clicks from the app — the signed-in door.

The anonymous one, for the website, is `POST /public/buy-click` in
`api/public.py`, beside the other public routes it belongs with.
"""

import uuid

from fastapi import APIRouter

from app.api.deps import CurrentUser, DbSession
from app.schemas.buy_click import BuyClicksIn, BuyClicksOut
from app.services import buy_click_service

router = APIRouter(prefix="/buy-clicks", tags=["buy-clicks"])


@router.post("", response_model=BuyClicksOut)
async def record_clicks(payload: BuyClicksIn, user: CurrentUser, db: DbSession) -> BuyClicksOut:
    """Batched taps from the device's outbox.

    Always 200, even when nothing is stored: a click on an edition that has
    since been removed, on a shop this server does not serve, or one already
    recorded, is dropped silently. An error would make the app's outbox retry
    a batch that can never succeed.
    """
    accepted = await buy_click_service.record_app(db, uuid.UUID(user["id"]), payload.events)
    return BuyClicksOut(accepted=accepted)
