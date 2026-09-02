"""SQLAlchemy model package — re-exports every ORM model and the shared mixins
so Alembic autogenerate and callers can import them from one place."""

from app.models.active_reading_session import ActiveReadingSession
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
from app.models.llm_usage import (
    FEATURE_COVER_EXTRACT,
    FEATURE_RECOMMENDATIONS,
    LLM_FEATURES,
    LlmUsage,
)
from app.models.merge_dismissal import MergeDismissal
from app.models.personal_tag import PersonalTag
from app.models.profile import Profile
from app.models.promotion import (
    ACTION_DEEP_LINK,
    ACTION_EXTERNAL_URL,
    ACTION_NONE,
    ACTIONS,
    CARD_BOOK,
    CARD_IMAGE,
    CARD_STYLES,
    CARD_TEXT,
    EVENT_CLICK,
    EVENT_DISMISS,
    EVENT_IMPRESSION,
    EVENT_KINDS,
    KIND_BANNER,
    KIND_CARD,
    KINDS,
    PLACEMENT_HOME_STREAM,
    PLACEMENT_HOME_TOP,
    PLACEMENTS,
    STATE_DRAFT,
    STATE_ENDED,
    STATE_LIVE,
    STATE_PAUSED,
    STATE_SCHEDULED,
    STATUS_DRAFT,
    STATUS_PAUSED,
    STATUS_PUBLISHED,
    STATUSES,
    Promotion,
    PromotionContent,
    PromotionEvent,
)
from app.models.publisher import Publisher
from app.models.rating import Rating
from app.models.reading_note import ReadingNote
from app.models.reading_session import ReadingSession
from app.models.rec_cache import RecCache
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
    "RecCache",
    "ReadingNote",
    "ReadingSession",
    "Review",
    "PersonalTag",
    "LibraryEntryTag",
    "LendingRecord",
    "Connection",
    "DeviceToken",
    "ActiveReadingSession",
    "ActivityLogEntry",
    "SyncOp",
    "ConflictHistory",
    "WorkRevision",
    "MergeDismissal",
    "LlmUsage",
    "LLM_FEATURES",
    "FEATURE_RECOMMENDATIONS",
    "FEATURE_COVER_EXTRACT",
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
    "Promotion",
    "PromotionContent",
    "PromotionEvent",
    "KINDS",
    "KIND_BANNER",
    "KIND_CARD",
    "CARD_STYLES",
    "CARD_BOOK",
    "CARD_IMAGE",
    "CARD_TEXT",
    "PLACEMENTS",
    "PLACEMENT_HOME_TOP",
    "PLACEMENT_HOME_STREAM",
    "STATUSES",
    "STATUS_DRAFT",
    "STATUS_PUBLISHED",
    "STATUS_PAUSED",
    "STATE_DRAFT",
    "STATE_SCHEDULED",
    "STATE_LIVE",
    "STATE_PAUSED",
    "STATE_ENDED",
    "ACTIONS",
    "ACTION_NONE",
    "ACTION_DEEP_LINK",
    "ACTION_EXTERNAL_URL",
    "EVENT_KINDS",
    "EVENT_IMPRESSION",
    "EVENT_CLICK",
    "EVENT_DISMISS",
]
