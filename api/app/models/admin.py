"""Admin-console identity and trust tables — deliberately separate from reader
identity (docs/admin_mockups.html). A reader is a Supabase Auth user with a
`profiles` row; an admin is a row here with its own password hash and TOTP
secret, and there is no path from one to the other. These tables live with the
rest of the schema (one Alembic history) but are touched only by the admin app.

RLS is enabled with zero policies on all of them, like every other table
(CLAUDE.md rule 11) — only the API/admin process, connecting as the table
owner, reads them.
"""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

# Roles, least to most powerful. A moderator works the queues; an editor also
# fixes the catalog; a super admin also manages admins and erases reader data.
ROLE_MODERATOR = "moderator"
ROLE_EDITOR = "editor"
ROLE_SUPER_ADMIN = "super_admin"
ADMIN_ROLES = (ROLE_MODERATOR, ROLE_EDITOR, ROLE_SUPER_ADMIN)


class AdminUser(Base):
    """A back-office operator. `password_hash` is Argon2id; `totp_secret` is set
    at creation but only trusted once `totp_enrolled_at` is stamped (an admin
    who hasn't confirmed their authenticator can reach nothing but enrolment)."""

    __tablename__ = "admin_users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    totp_secret: Mapped[str | None] = mapped_column(String, default=None)
    totp_enrolled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    role: Mapped[str] = mapped_column(String, nullable=False, default=ROLE_MODERATOR)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Who created this admin (null for the seeded founder). Not an FK to itself
    # so removing an admin never cascades away the record of who they added.
    created_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    last_sign_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    # Brute-force guard: N failures locks the account until locked_until.
    failed_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class AdminRecoveryCode(Base):
    """One single-use backup code for an admin who loses their authenticator.
    Stored hashed and shown to the admin exactly once, at enrolment."""

    __tablename__ = "admin_recovery_codes"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    admin_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("admin_users.id"), nullable=False, index=True
    )
    code_hash: Mapped[str] = mapped_column(String, nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class AdminSession(Base):
    """A signed-in admin session. The cookie holds an opaque token; only its
    hash is stored, so a leaked database row can't be replayed as a session."""

    __tablename__ = "admin_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    admin_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("admin_users.id"), nullable=False, index=True
    )
    token_hash: Mapped[str] = mapped_column(String, unique=True, nullable=False, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ip: Mapped[str | None] = mapped_column(String, default=None)
    user_agent: Mapped[str | None] = mapped_column(String, default=None)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class AdminAuditLog(Base):
    """Append-only record of everything an admin does that changes shared data
    or another account — and every sign-in attempt, successful or not. No
    updated_at, no delete path: the trail is what makes the console defensible.
    `admin_id` is nullable so a failed sign-in (no known admin yet) still logs."""

    __tablename__ = "admin_audit_log"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None, index=True)
    # A dotted verb: claim.approve, work.merge, review.hide, admin.invite, auth.fail…
    action: Mapped[str] = mapped_column(String, nullable=False, index=True)
    target_type: Mapped[str | None] = mapped_column(String, default=None)
    target_id: Mapped[str | None] = mapped_column(String, default=None)
    summary: Mapped[str | None] = mapped_column(String, default=None)
    ip: Mapped[str | None] = mapped_column(String, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )


# Report statuses.
REPORT_OPEN = "open"
REPORT_UPHELD = "upheld"
REPORT_DISMISSED = "dismissed"


class ContentReport(Base):
    """[WIRED] A reader's report of a public review (the only reader-written
    text other readers see today). The report button ships now; the queue stays
    quiet until there's traffic. Hiding sets the review's visibility flag —
    soft, reversible, logged — it never destroys the row."""

    __tablename__ = "content_reports"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    reporter_user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(String, nullable=False)  # "review" for now
    target_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    reason: Mapped[str | None] = mapped_column(String, default=None)
    status: Mapped[str] = mapped_column(String, nullable=False, default=REPORT_OPEN, index=True)
    decided_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
