"""Pydantic schema for FCM device-token registration."""

from pydantic import BaseModel


class DeviceTokenIn(BaseModel):
    token: str
    platform: str | None = None  # ios | android
    # The install this token belongs to (the sync engine's device id). Optional:
    # an older build doesn't send it, and unregister only needs the token.
    device_id: str | None = None
