"""Devices router: register/unregister an install's FCM push token for the
signed-in user."""

import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.device import DeviceTokenIn
from app.services import device_service

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
async def register_device(payload: DeviceTokenIn, user: CurrentUser, db: DbSession) -> None:
    """Register this install's FCM token for the signed-in user (idempotent)."""
    await device_service.register(db, uuid.UUID(user["id"]), payload.token, payload.platform)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device(payload: DeviceTokenIn, user: CurrentUser, db: DbSession) -> None:
    """Drop this token on sign-out so the device stops receiving pushes."""
    await device_service.unregister(db, payload.token)
