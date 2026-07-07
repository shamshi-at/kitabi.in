"""Pydantic request/response schemas for user profiles: profile read/update,
username validation, public user search, and scoring."""

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
    # The reader's languages (e.g. ["Malayalam", "English"]) — set at onboarding,
    # editable in profile; drives the add-book language dropdown.
    preferred_languages: list[str] = []
    # Reputation total, computed at read time from contributions + activity.
    score: int = 0
    created_at: datetime
    updated_at: datetime

    @field_validator("preferred_languages", mode="before")
    @classmethod
    def _null_langs_to_empty(cls, v: object) -> object:
        return v if v is not None else []


class ProfileUpdate(BaseModel):
    username: str | None = None
    full_name: str | None = None
    profile_visible: bool | None = None
    library_visible: bool | None = None
    reviews_visible_default: bool | None = None
    preferred_languages: list[str] | None = None

    @field_validator("username")
    @classmethod
    def _validate_username(cls, v: str | None) -> str | None:
        return normalize_username(v)

    @field_validator("preferred_languages")
    @classmethod
    def _clean_langs(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        # Trim, drop blanks, de-duplicate while preserving order.
        seen: dict[str, None] = {}
        for lang in v:
            name = lang.strip()
            if name:
                seen.setdefault(name, None)
        return list(seen.keys())


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
