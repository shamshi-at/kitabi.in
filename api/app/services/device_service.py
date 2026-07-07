"""Device FCM token registry — upsert a push token, (re)binding it to the signed-in
user so a stale row can never push to a prior account, and unregister on sign-out."""

import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device_token import DeviceToken


async def register(db: AsyncSession, user_id: uuid.UUID, token: str, platform: str | None) -> None:
    """Upsert an FCM token, (re)binding it to the signed-in user. A token is
    unique, so if it already exists (same device, possibly a different account
    last time) we reassign it rather than duplicate — a stale row can never push
    to the wrong account."""
    existing = (
        await db.execute(select(DeviceToken).where(DeviceToken.token == token))
    ).scalar_one_or_none()
    if existing is not None:
        existing.user_id = user_id
        existing.platform = platform
    else:
        db.add(DeviceToken(user_id=user_id, token=token, platform=platform))
    await db.commit()


async def unregister(db: AsyncSession, token: str) -> None:
    """Drop a token on sign-out so a shared device stops receiving pushes."""
    await db.execute(delete(DeviceToken).where(DeviceToken.token == token))
    await db.commit()


async def tokens_for_user(db: AsyncSession, user_id: uuid.UUID) -> list[str]:
    rows = (
        (await db.execute(select(DeviceToken.token).where(DeviceToken.user_id == user_id)))
        .scalars()
        .all()
    )
    return list(rows)


async def prune(db: AsyncSession, tokens: list[str]) -> None:
    """Delete tokens FCM reported as unregistered/invalid."""
    if not tokens:
        return
    await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(tokens)))
    await db.commit()
