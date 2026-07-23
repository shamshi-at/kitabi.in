"""Re-export the API's models through one import, after bootstrapping the path.

Everything in the admin app imports models from here so the `sys.path` shim in
bootstrap.py runs exactly once and no module has to repeat it.
"""

from . import bootstrap as _bootstrap  # noqa: F401 — side effect: extend sys.path

from app.core.db import SessionLocal  # noqa: E402
from app.models import (  # noqa: E402
    ADMIN_ROLES,
    CLAIM_APPROVED,
    CLAIM_PENDING,
    CLAIM_REJECTED,
    REPORT_OPEN,
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
)

__all__ = [
    "SessionLocal",
    "AdminUser",
    "AdminRecoveryCode",
    "AdminSession",
    "AdminAuditLog",
    "ContentReport",
    "ADMIN_ROLES",
    "ROLE_MODERATOR",
    "ROLE_EDITOR",
    "ROLE_SUPER_ADMIN",
    "REPORT_OPEN",
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
