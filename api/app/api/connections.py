import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.connection import (
    ConnectionRequestIn,
    ConnectionsOut,
    ConnectionStatusOut,
)
from app.services import connection_service

router = APIRouter(prefix="/connections", tags=["connections"])


@router.get("", response_model=ConnectionsOut)
async def list_connections(user: CurrentUser, db: DbSession) -> ConnectionsOut:
    """Everything for the connections screen: requests to approve (incoming),
    requests you've sent (outgoing), and confirmed connections (accepted)."""
    return await connection_service.list_for(db, uuid.UUID(user["id"]))


@router.get("/status/{user_id}", response_model=ConnectionStatusOut)
async def connection_status(
    user_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> ConnectionStatusOut:
    """Where you stand with one specific user — the lend flow uses this to decide
    auto-link (accepted) vs send-a-request."""
    return await connection_service.status_with(db, uuid.UUID(user["id"]), user_id)


@router.post("", response_model=ConnectionStatusOut, status_code=status.HTTP_201_CREATED)
async def request_connection(
    payload: ConnectionRequestIn, user: CurrentUser, db: DbSession
) -> ConnectionStatusOut:
    """Ask to connect (or, if they already asked you, this accepts). Idempotent:
    re-requesting an existing pending/accepted connection just returns it."""
    me = uuid.UUID(user["id"])
    conn = await connection_service.request(db, me, payload.addressee_id)
    return connection_service.to_status(conn, me)


@router.post("/{connection_id}/accept", status_code=status.HTTP_204_NO_CONTENT)
async def accept_connection(connection_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    await connection_service.accept(db, uuid.UUID(user["id"]), connection_id)


@router.post("/{connection_id}/decline", status_code=status.HTTP_204_NO_CONTENT)
async def decline_connection(connection_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    """Deny an incoming request, cancel one you sent, or disconnect an accepted
    connection — lands on 'denied' (the other side may still re-send)."""
    await connection_service.decline(db, uuid.UUID(user["id"]), connection_id)


@router.post("/{connection_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def block_connection(connection_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    """Block the other party — terminal; they can't re-send past it."""
    await connection_service.block(db, uuid.UUID(user["id"]), connection_id)


@router.post("/{connection_id}/unblock", status_code=status.HTTP_204_NO_CONTENT)
async def unblock_connection(connection_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    """Undo a block (blocker only) — the connection returns to 'denied'."""
    await connection_service.unblock(db, uuid.UUID(user["id"]), connection_id)
