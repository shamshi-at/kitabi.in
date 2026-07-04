import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ProfileOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    full_name: str | None
    avatar_url: str | None
    profile_visible: bool
    library_visible: bool
    reviews_visible_default: bool
    created_at: datetime
    updated_at: datetime


class ProfileUpdate(BaseModel):
    full_name: str | None = None
    profile_visible: bool | None = None
    library_visible: bool | None = None
    reviews_visible_default: bool | None = None
