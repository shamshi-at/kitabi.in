import re
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_validator

# 3–20 chars, lowercase letters/digits/underscore, must start with a letter.
_USERNAME_RE = re.compile(r"^[a-z][a-z0-9_]{2,19}$")


def normalize_username(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if not _USERNAME_RE.match(normalized):
        raise ValueError(
            "Username must be 3–20 characters: a letter, then letters, digits or underscores."
        )
    return normalized


class ProfileOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    username: str | None
    full_name: str | None
    avatar_url: str | None
    profile_visible: bool
    library_visible: bool
    reviews_visible_default: bool
    # Reputation total, computed at read time from contributions + activity.
    score: int = 0
    created_at: datetime
    updated_at: datetime


class ProfileUpdate(BaseModel):
    username: str | None = None
    full_name: str | None = None
    profile_visible: bool | None = None
    library_visible: bool | None = None
    reviews_visible_default: bool | None = None

    @field_validator("username")
    @classmethod
    def _validate_username(cls, v: str | None) -> str | None:
        return normalize_username(v)


class UsernameAvailableOut(BaseModel):
    username: str
    available: bool


class ScoreOut(BaseModel):
    """The reputation breakdown shown on the profile — what earned each slice
    of points, plus the total."""

    total: int
    books_added: int
    authors_added: int
    reviews_written: int
    books_tracked: int
    books_finished: int
    lending_records: int


class UserSearchOut(BaseModel):
    """Minimal public shape for finding a reader by username (lending). Only
    users who've set a username are findable; nothing private is exposed."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    username: str
    full_name: str | None
    avatar_url: str | None
