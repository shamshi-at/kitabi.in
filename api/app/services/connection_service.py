"""Reader-to-reader connections — request / accept / block over a single deduped
Connection row per pair, resolved to a directional status (pending_in/out) for the
viewer. Wired now to back linked lending (feature-map.md); the future community graph
grows from the same table."""

import uuid

from fastapi import HTTPException, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.connection import Connection
from app.models.profile import Profile
from app.schemas.connection import (
    ConnectionOut,
    ConnectionsOut,
    ConnectionStatusOut,
    ConnectionUserOut,
)


async def _pair(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> Connection | None:
    """The single connection row between a and b, in either direction (all
    creation goes through `request`, which dedupes, so there's at most one)."""
    stmt = select(Connection).where(
        or_(
            and_(Connection.requester_id == a, Connection.addressee_id == b),
            and_(Connection.requester_id == b, Connection.addressee_id == a),
        )
    )
    return (await db.execute(stmt)).scalars().first()


def to_status(conn: Connection | None, me: uuid.UUID) -> ConnectionStatusOut:
    if conn is None:
        return ConnectionStatusOut(status="none")
    if conn.status == "pending":
        role = "pending_out" if conn.requester_id == me else "pending_in"
        return ConnectionStatusOut(status=role, connection_id=conn.id)
    return ConnectionStatusOut(status=conn.status, connection_id=conn.id)


async def request(db: AsyncSession, me: uuid.UUID, addressee_id: uuid.UUID) -> Connection:
    if addressee_id == me:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "self_connection", "message": "You can't connect to yourself"},
        )
    addressee = await db.get(Profile, addressee_id)
    if addressee is None or addressee.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "user_not_found", "message": "No such user"},
        )

    existing = await _pair(db, me, addressee_id)
    if existing is not None:
        if existing.status == "accepted":
            return existing
        if existing.status == "pending":
            # They already asked me → my request is an acceptance (mutual intent).
            if existing.addressee_id == me:
                existing.status = "accepted"
                await db.commit()
                await db.refresh(existing)
            return existing
        if existing.status == "blocked" and existing.blocked_by != me:
            # The other party blocked me — a denied request can be re-sent, a
            # blocked one can't (that's the whole point of blocking).
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"code": "blocked", "message": "You can't send this request"},
            )
        # Denied (re-send), or blocked-by-me (I change my mind → unblock): reopen
        # as a fresh pending request from me.
        existing.requester_id = me
        existing.addressee_id = addressee_id
        existing.status = "pending"
        existing.blocked_by = None
        await db.commit()
        await db.refresh(existing)
        return existing

    conn = Connection(requester_id=me, addressee_id=addressee_id, status="pending")
    db.add(conn)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raced = await _pair(db, me, addressee_id)
        if raced is not None:
            return raced
        raise
    await db.refresh(conn)
    return conn


async def status_with(db: AsyncSession, me: uuid.UUID, other_id: uuid.UUID) -> ConnectionStatusOut:
    return to_status(await _pair(db, me, other_id), me)


async def count_accepted(db: AsyncSession, user_id: uuid.UUID) -> int:
    """How many accepted connections a reader has — shown as a stat on their
    public profile."""
    stmt = (
        select(func.count())
        .select_from(Connection)
        .where(
            Connection.status == "accepted",
            or_(Connection.requester_id == user_id, Connection.addressee_id == user_id),
        )
    )
    return (await db.execute(stmt)).scalar_one()


async def are_connected(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> bool:
    """True iff a and b have an accepted connection — the gate for mirroring a
    loan onto the counterparty's account."""
    conn = await _pair(db, a, b)
    return conn is not None and conn.status == "accepted"


async def list_for(db: AsyncSession, me: uuid.UUID) -> ConnectionsOut:
    rows = list(
        (
            await db.execute(
                select(Connection).where(
                    or_(Connection.requester_id == me, Connection.addressee_id == me)
                )
            )
        )
        .scalars()
        .all()
    )
    other_ids = {r.addressee_id if r.requester_id == me else r.requester_id for r in rows}
    profiles: dict[uuid.UUID, Profile] = {}
    if other_ids:
        found = (await db.execute(select(Profile).where(Profile.id.in_(other_ids)))).scalars().all()
        profiles = {p.id: p for p in found}

    def to_out(r: Connection) -> ConnectionOut:
        role = "requester" if r.requester_id == me else "addressee"
        other_id = r.addressee_id if role == "requester" else r.requester_id
        p = profiles.get(other_id)
        return ConnectionOut(
            id=r.id,
            status=r.status,
            role=role,
            other=ConnectionUserOut(
                id=other_id,
                username=p.username if p else None,
                full_name=p.full_name if p else None,
                avatar_url=p.avatar_url if p else None,
            ),
            created_at=r.created_at,
        )

    return ConnectionsOut(
        incoming=[to_out(r) for r in rows if r.status == "pending" and r.addressee_id == me],
        outgoing=[to_out(r) for r in rows if r.status == "pending" and r.requester_id == me],
        accepted=[to_out(r) for r in rows if r.status == "accepted"],
        # Requests I sent that were denied — I can re-send these (until blocked).
        rejected=[to_out(r) for r in rows if r.status == "denied" and r.requester_id == me],
        # People I've blocked — I can unblock them.
        blocked=[to_out(r) for r in rows if r.status == "blocked" and r.blocked_by == me],
    )


async def _owned(db: AsyncSession, me: uuid.UUID, conn_id: uuid.UUID) -> Connection:
    conn = await db.get(Connection, conn_id)
    if conn is None or (conn.requester_id != me and conn.addressee_id != me):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Connection not found"},
        )
    return conn


async def accept(db: AsyncSession, me: uuid.UUID, conn_id: uuid.UUID) -> Connection:
    conn = await _owned(db, me, conn_id)
    if conn.addressee_id != me:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "not_addressee", "message": "Only the addressee can accept"},
        )
    if conn.status == "pending":
        conn.status = "accepted"
        await db.commit()
        await db.refresh(conn)
    return conn


async def decline(db: AsyncSession, me: uuid.UUID, conn_id: uuid.UUID) -> Connection:
    """Deny an incoming request, cancel an outgoing one, or disconnect an
    accepted connection — any party, lands on 'denied' (the other side may still
    re-send). Use `block` to make it terminal."""
    conn = await _owned(db, me, conn_id)
    conn.status = "denied"
    conn.blocked_by = None
    await db.commit()
    await db.refresh(conn)
    return conn


async def block(db: AsyncSession, me: uuid.UUID, conn_id: uuid.UUID) -> Connection:
    """Block the other party — a terminal 'denied' they can't re-send past. Only
    the blocker can undo it (`unblock`)."""
    conn = await _owned(db, me, conn_id)
    conn.status = "blocked"
    conn.blocked_by = me
    await db.commit()
    await db.refresh(conn)
    return conn


async def unblock(db: AsyncSession, me: uuid.UUID, conn_id: uuid.UUID) -> Connection:
    conn = await _owned(db, me, conn_id)
    if conn.blocked_by != me:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "not_blocker", "message": "Only the blocker can unblock"},
        )
    conn.status = "denied"
    conn.blocked_by = None
    await db.commit()
    await db.refresh(conn)
    return conn
