"""The in-app inbox (models/inbox_notification.py): record what a reader was
told, list it, mark it read, clear it.

`record` runs on the caller's own session and leaves the commit to it, so it
lands with the event it describes. It deliberately does not live inside
push_service, whose functions open their own sessions from the configured
database URL — under test that would reach whatever `api/.env` points at.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.inbox_notification import InboxNotification
from app.models.profile import Profile
from app.schemas.inbox import InboxActorOut, InboxItemOut, InboxOut
from app.services import notification_text

# The bell shows the latest of these; older ones are kept, just not sent.
LIST_LIMIT = 60


def _name(p: Profile | None) -> str:
    if p is None:
        return "Someone"
    if p.full_name and p.full_name.strip():
        return p.full_name.strip()
    if p.username:
        return f"@{p.username}"
    return "Someone"


async def record(
    db: AsyncSession,
    *,
    recipient_id: uuid.UUID,
    actor_id: uuid.UUID,
    kind: str,
    book_title: str | None = None,
    data: dict[str, str] | None = None,
    image_url: str | None = None,
) -> None:
    """Write one inbox row in the words the push uses. The caller commits.

    An identical row still sitting unread is not written twice — re-tapping
    "Connect" on a pending request re-runs the same endpoint, and the bell
    should say it once."""
    full_data = {"type": kind, **(data or {})}
    duplicate = (
        await db.execute(
            select(InboxNotification.id).where(
                _visible(recipient_id),
                InboxNotification.read_at.is_(None),
                InboxNotification.actor_id == actor_id,
                InboxNotification.type == kind,
                InboxNotification.data == full_data,
            )
        )
    ).first()
    if duplicate is not None:
        return
    title, suffix = notification_text.render(kind, book_title)
    actor = await db.get(Profile, actor_id)
    db.add(
        InboxNotification(
            user_id=recipient_id,
            actor_id=actor_id,
            type=kind,
            title=title,
            body=f"{_name(actor)} {suffix}",
            data=full_data,
            image_url=image_url,
        )
    )
    await db.flush()


def _visible(me: uuid.UUID):  # noqa: ANN202 — a SQLAlchemy clause
    return (InboxNotification.user_id == me) & InboxNotification.cleared_at.is_(None)


async def unread_count(db: AsyncSession, me: uuid.UUID) -> int:
    return (
        await db.execute(
            select(func.count())
            .select_from(InboxNotification)
            .where(_visible(me), InboxNotification.read_at.is_(None))
        )
    ).scalar_one()


async def list_for(db: AsyncSession, me: uuid.UUID) -> InboxOut:
    rows = (
        (
            await db.execute(
                select(InboxNotification)
                .where(_visible(me))
                .order_by(InboxNotification.created_at.desc())
                .limit(LIST_LIMIT)
            )
        )
        .scalars()
        .all()
    )
    actor_ids = {r.actor_id for r in rows if r.actor_id is not None}
    actors: dict[uuid.UUID, Profile] = {}
    if actor_ids:
        found = (await db.execute(select(Profile).where(Profile.id.in_(actor_ids)))).scalars()
        actors = {p.id: p for p in found.all()}
    items = []
    for r in rows:
        actor = actors.get(r.actor_id) if r.actor_id else None
        items.append(
            InboxItemOut(
                id=r.id,
                type=r.type,
                title=r.title,
                body=r.body,
                data={k: str(v) for k, v in (r.data or {}).items()},
                image_url=r.image_url,
                created_at=r.created_at,
                read=r.read_at is not None,
                actor=(
                    InboxActorOut(id=actor.id, name=_name(actor), avatar_url=actor.avatar_url)
                    if actor is not None
                    else None
                ),
            )
        )
    return InboxOut(unread=await unread_count(db, me), items=items)


async def mark_read(db: AsyncSession, me: uuid.UUID, ids: list[uuid.UUID] | None) -> None:
    """Mark the given notifications (or, with None, all of them) read."""
    stmt = (
        update(InboxNotification)
        .where(_visible(me), InboxNotification.read_at.is_(None))
        .values(read_at=datetime.now(UTC))
    )
    if ids is not None:
        stmt = stmt.where(InboxNotification.id.in_(ids))
    await db.execute(stmt)
    await db.commit()


async def clear(db: AsyncSession, me: uuid.UUID) -> None:
    """ "Clear" empties the bell. Soft (rule 3): the rows stay, out of sight."""
    now = datetime.now(UTC)
    await db.execute(
        update(InboxNotification)
        .where(_visible(me))
        .values(cleared_at=now, read_at=func.coalesce(InboxNotification.read_at, now))
    )
    await db.commit()
