"""Re-export the API's models through one import, after putting its package on
the path. Everything in the admin app imports models from here, so the `sys.path`
shim runs exactly once and no other module repeats it.
"""

import sys
from pathlib import Path

# Add the API package (<repo>/api) to the path BEFORE importing from it. Written
# as an inline statement, not an import, so an import-sorter can't reorder it
# after the `app.*` imports below and break the whole thing (it did — ruff's
# isort moved app.* above this and every admin import started 500-ing).
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "api"))

from app.core.db import SessionLocal  # noqa: E402
from app.models import (  # noqa: E402
    ADMIN_ROLES,
    CLAIM_APPROVED,
    CLAIM_PENDING,
    CLAIM_REJECTED,
    REPORT_DISMISSED,
    REPORT_OPEN,
    REPORT_UPHELD,
    ROLE_EDITOR,
    ROLE_MODERATOR,
    ROLE_SUPER_ADMIN,
    AdminAuditLog,
    AdminRecoveryCode,
    AdminSession,
    AdminUser,
    Author,
    AuthorClaim,
    ContentReport,
    Edition,
    LibraryEntry,
    Profile,
    Publisher,
    Rating,
    ReadingSession,
    Review,
    Work,
    WorkRevision,
)

__all__ = [
    "SessionLocal",
    "AdminUser",
    "AdminRecoveryCode",
    "AdminSession",
    "AdminAuditLog",
    "ContentReport",
    "WorkRevision",
    "ADMIN_ROLES",
    "ROLE_MODERATOR",
    "ROLE_EDITOR",
    "ROLE_SUPER_ADMIN",
    "REPORT_OPEN",
    "REPORT_UPHELD",
    "REPORT_DISMISSED",
    "Author",
    "AuthorClaim",
    "CLAIM_PENDING",
    "CLAIM_APPROVED",
    "CLAIM_REJECTED",
    "Profile",
    "Work",
    "Edition",
    "Publisher",
    "LibraryEntry",
    "Rating",
    "Review",
    "ReadingSession",
]
