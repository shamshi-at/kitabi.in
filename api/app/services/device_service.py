"""Device FCM token registry — upsert a push token, (re)binding it to the signed-in
user so a stale row can never push to a prior account, and unregister on sign-out."""

import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device_token import DeviceToken


async def register(
    db: AsyncSession,
    user_id: uuid.UUID,
    token: str,
    platform: str | None,
    device_id: str | None = None,
) -> None:
    """Upsert an FCM token, (re)binding it to the signed-in user. A token is
    unique, so if it already exists (same device, possibly a different account
    last time) we reassign it rather than duplicate — a stale row can never push
    to the wrong account.

    `device_id` says which install this token belongs to, so a fan-out can leave
    the originating device out. Never overwrite a known id with None: an older
    build re-registering must not blank what a newer one recorded."""
    existing = (
        await db.execute(select(DeviceToken).where(DeviceToken.token == token))
    ).scalar_one_or_none()
    if existing is not None:
        existing.user_id = user_id
        existing.platform = platform
        if device_id is not None:
            existing.device_id = device_id
    else:
        db.add(DeviceToken(user_id=user_id, token=token, platform=platform, device_id=device_id))
    await db.commit()


async def unregister(db: AsyncSession, token: str) -> None:
    """Drop a token on sign-out so a shared device stops receiving pushes."""
    await db.execute(delete(DeviceToken).where(DeviceToken.token == token))
    await db.commit()


async def tokens_for_user(
    db: AsyncSession, user_id: uuid.UUID, exclude_device_id: str | None = None
) -> list[str]:
    """Every push token on the account, optionally minus one install's.

    The exclusion is `IS DISTINCT FROM`, not `!=`: a row whose `device_id` is
    NULL (registered by a build that didn't send one) compares NULL under `!=`
    and would be dropped from *every* fan-out — silently losing pushes to a
    device rather than the intended one. NULL is "some other device" here."""
    stmt = select(DeviceToken.token).where(DeviceToken.user_id == user_id)
    if exclude_device_id:
        stmt = stmt.where(DeviceToken.device_id.is_distinct_from(exclude_device_id))
    rows = (await db.execute(stmt)).scalars().all()
    return list(rows)


async def prune(db: AsyncSession, tokens: list[str]) -> None:
    """Delete tokens FCM reported as unregistered/invalid."""
    if not tokens:
        return
    await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(tokens)))
    await db.commit()
