"""Shared FastAPI dependency aliases: `CurrentUser` (verified Supabase JWT
claims) and `DbSession` (request-scoped async DB session)."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.security import get_current_user

CurrentUser = Annotated[dict, Depends(get_current_user)]
DbSession = Annotated[AsyncSession, Depends(get_db)]
