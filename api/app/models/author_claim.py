"""A reader's "This is me" claim on a catalog Author — pending manual review.

Self-declared authorship is unverifiable and sits on *shared* catalog data, so
it no longer applies on submission (owner decision, 22 Jul 2026; the button was
hidden entirely in 2fccf1f until this queue existed). A claim lands here as
`pending`: the claimant sees their own claim's state, every other reader keeps
seeing `authors.linked_user_id` exactly as it was. Approval flips that column;
until then nothing about the shared row changes.

This supersedes the "no claim workflow" line in
docs/author-identity-and-moderation-plan.md, which assumed an invited friend
circle where the trust check happened outside the app.

Approval is manual for now — no endpoint, no admin UI (deliberately deferred).
`approve_claim` / `reject_claim` in catalog_service are the whole decision path;
a moderator endpoint can call them later without changing this shape.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

CLAIM_PENDING = "pending"
CLAIM_APPROVED = "approved"
CLAIM_REJECTED = "rejected"


class AuthorClaim(Base):
    __tablename__ = "author_claims"
    # One claim per reader per author. Two different readers may both have a
    # pending claim on the same author — that is the case a review queue exists
    # to settle, so it must be representable.
    __table_args__ = (
        UniqueConstraint("author_id", "user_id", name="uq_author_claims_author_user"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    author_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("authors.id"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    status: Mapped[str] = mapped_column(String, nullable=False, default=CLAIM_PENDING, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    decided_by_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
