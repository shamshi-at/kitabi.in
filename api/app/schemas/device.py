from pydantic import BaseModel


class DeviceTokenIn(BaseModel):
    token: str
    platform: str | None = None  # ios | android
