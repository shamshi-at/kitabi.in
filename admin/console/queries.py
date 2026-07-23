"""Read-only aggregate queries for the dashboard and the nav badges. Kept apart
from the API's own services because these are admin-shaped questions ("how many
are waiting on me") the reader API never asks."""

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .models_ref import (
    CLAIM_PENDING,
    REPORT_OPEN,
    AdminUser,
    AuthorClaim,
    Author,
    ContentReport,
    Edition,
    LibraryEntry,
    Profile,
    Work,
)

# WorkRevision lives in the API models but the admin app doesn't re-export it;
# import lazily where needed to keep models_ref small.


async def _count(db: AsyncSession, stmt) -> int:
    return int(await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0)


async def pending_claims(db: AsyncSession) -> int:
    return int(
        await db.scalar(
            select(func.count())
            .select_from(AuthorClaim)
            .where(AuthorClaim.status == CLAIM_PENDING)
        )
        or 0
    )


async def pending_revisions(db: AsyncSession) -> int:
    from app.models import WorkRevision  # noqa: PLC0415 — lazy, see module docstring

    return int(
        await db.scalar(
            select(func.count())
            .select_from(WorkRevision)
            .where(WorkRevision.status == "pending")
        )
        or 0
    )


async def open_reports(db: AsyncSession) -> int:
    return int(
        await db.scalar(
            select(func.count())
            .select_from(ContentReport)
            .where(ContentReport.status == REPORT_OPEN)
        )
        or 0
    )


async def nav_badges(db: AsyncSession) -> dict:
    claims = await pending_claims(db)
    revisions = await pending_revisions(db)
    reports = await open_reports(db)
    return {
        "claims": claims,
        "revisions": revisions,
        "reports": reports,
        "waiting_total": claims + revisions + reports,
    }


async def dashboard_stats(db: AsyncSession) -> dict:
    """The KPI row and the health panel. Counts are cheap COUNTs over indexed
    columns; a personal-scale catalog makes them instant."""
    active = LibraryEntry.deleted_at.is_(None)
    readers = int(await db.scalar(select(func.count()).select_from(Profile)) or 0)
    works = int(
        await db.scalar(
            select(func.count()).select_from(Work).where(Work.deleted_at.is_(None))
        )
        or 0
    )
    editions = int(
        await db.scalar(
            select(func.count())
            .select_from(Edition)
            .where(Edition.deleted_at.is_(None))
        )
        or 0
    )
    shelved = int(
        await db.scalar(select(func.count()).select_from(LibraryEntry).where(active))
        or 0
    )
    authors = int(
        await db.scalar(
            select(func.count()).select_from(Author).where(Author.deleted_at.is_(None))
        )
        or 0
    )
    admins = int(await db.scalar(select(func.count()).select_from(AdminUser)) or 0)

    # Catalog health — the columns a bulk seed leaves thin.
    with_cover = int(
        await db.scalar(
            select(func.count())
            .select_from(Edition)
            .where(Edition.deleted_at.is_(None), Edition.cover_url.is_not(None))
        )
        or 0
    )
    with_desc = int(
        await db.scalar(
            select(func.count())
            .select_from(Work)
            .where(Work.deleted_at.is_(None), Work.description.is_not(None))
        )
        or 0
    )
    with_isbn = int(
        await db.scalar(
            select(func.count())
            .select_from(Edition)
            .where(Edition.deleted_at.is_(None), Edition.isbn.is_not(None))
        )
        or 0
    )

    def pct(n: int, d: int) -> int:
        return round(100 * n / d) if d else 0

    badges = await nav_badges(db)
    return {
        "readers": readers,
        "works": works,
        "editions": editions,
        "shelved": shelved,
        "authors": authors,
        "admins": admins,
        "waiting": badges["waiting_total"],
        "health": {
            "cover_pct": pct(with_cover, editions),
            "desc_pct": pct(with_desc, works),
            "isbn_pct": pct(with_isbn, editions),
        },
        "badges": badges,
    }
