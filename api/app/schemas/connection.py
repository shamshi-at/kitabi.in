import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ConnectionUserOut(BaseModel):
    """The *other* party in a connection — minimal public shape, same as user
    search. Never exposes anything private."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    username: str | None
    full_name: str | None


class ConnectionOut(BaseModel):
    """One connection from the caller's point of view. `role` says whether the
    caller sent the request ('requester') or received it ('addressee'), so the
    app can render "you asked" vs "asked you"."""

    id: uuid.UUID
    status: str  # pending | accepted | denied
    role: str  # requester | addressee
    other: ConnectionUserOut
    created_at: datetime


class ConnectionsOut(BaseModel):
    """The connections screen in one call: requests to approve, requests you've
    sent, and confirmed connections."""

    incoming: list[ConnectionOut]  # pending, addressed to you — approve/deny/block
    outgoing: list[ConnectionOut]  # pending, sent by you — awaiting them
    accepted: list[ConnectionOut]
    rejected: list[ConnectionOut]  # you sent, they denied — you can re-send
    blocked: list[ConnectionOut]  # you blocked — you can unblock


class ConnectionRequestIn(BaseModel):
    addressee_id: uuid.UUID


class RemindIn(BaseModel):
    """Nudge a connected borrower to return a book. `book_title` is display-only."""

    user_id: uuid.UUID
    book_title: str = "a book"


class ConnectionStatusOut(BaseModel):
    """Where the caller stands with one specific user — drives the lend flow's
    auto-link vs request decision, and the pending pill on the ledger.

    'none' | 'pending_out' (you asked) | 'pending_in' (they asked) |
    'accepted' | 'denied'.
    """

    status: str
    connection_id: uuid.UUID | None = None
