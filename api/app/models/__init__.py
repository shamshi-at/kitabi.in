"""SQLAlchemy model package — re-exports every ORM model and the shared mixins
so Alembic autogenerate and callers can import them from one place."""

from app.models.activity_log_entry import ActivityLogEntry
from app.models.admin import (
    ADMIN_ROLES,
    REPORT_DISMISSED,
    REPORT_OPEN,
    REPORT_UPHELD,
    ROLE_EDITOR,
    ROLE_MODERATOR,
    ROLE_SUPER_ADMIN,
    TOKEN_INVITE,
    TOKEN_MAGIC,
    TOKEN_RESET,
    AdminAuditLog,
    AdminAuthToken,
    AdminRecoveryCode,
    AdminSession,
    AdminUser,
    ContentReport,
)
from app.models.author import Author
from app.models.author_claim import (
    CLAIM_APPROVED,
    CLAIM_PENDING,
    CLAIM_REJECTED,
    AuthorClaim,
)
from app.models.base import Base, CatalogMixin, SyncableMixin
from app.models.conflict_history import ConflictHistory
from app.models.connection import Connection
from app.models.device_token import DeviceToken
from app.models.edition import Edition
from app.models.genre import Genre
from app.models.lending_record import LendingRecord
from app.models.library_entry import LibraryEntry
from app.models.library_entry_tag import LibraryEntryTag
from app.models.personal_tag import PersonalTag
from app.models.profile import Profile
from app.models.publisher import Publisher
from app.models.rating import Rating
from app.models.reading_note import ReadingNote
from app.models.reading_session import ReadingSession
from app.models.review import Review
from app.models.series import Series
from app.models.sync_op import SyncOp
from app.models.work import Work, work_authors, work_genres, work_translators
from app.models.work_revision import WorkRevision

# Side-effect import: registers the before_insert/before_update listeners that
# maintain the cross-script *_translit search columns.
from app.models import translit_hooks as _translit_hooks  # noqa: E402,F401  isort:skip

__all__ = [
    "Base",
    "SyncableMixin",
    "CatalogMixin",
    "Profile",
    "Author",
    "AuthorClaim",
    "CLAIM_PENDING",
    "CLAIM_APPROVED",
    "CLAIM_REJECTED",
    "Publisher",
    "Genre",
    "Series",
    "Work",
    "Edition",
    "work_authors",
    "work_genres",
    "work_translators",
    "LibraryEntry",
    "Rating",
    "ReadingNote",
    "ReadingSession",
    "Review",
    "PersonalTag",
    "LibraryEntryTag",
    "LendingRecord",
    "Connection",
    "DeviceToken",
    "ActivityLogEntry",
    "SyncOp",
    "ConflictHistory",
    "WorkRevision",
    "AdminUser",
    "AdminRecoveryCode",
    "AdminSession",
    "AdminAuditLog",
    "AdminAuthToken",
    "ContentReport",
    "TOKEN_RESET",
    "TOKEN_MAGIC",
    "TOKEN_INVITE",
    "ADMIN_ROLES",
    "ROLE_MODERATOR",
    "ROLE_EDITOR",
    "ROLE_SUPER_ADMIN",
    "REPORT_OPEN",
    "REPORT_UPHELD",
    "REPORT_DISMISSED",
]
