"""Reputation scoring — StackOverflow-style points earned from contributions
and activity. Computed at read time from the countable rows a user owns
(no separate ledger to keep in sync); cheap COUNTs, all indexed by owner.

Points a reader earns:
- contributing a book to the catalog        +10  (created_by_user_id on works)
- contributing an author                    +5   (created_by_user_id on authors)
- writing a review                           +10
- tracking a book (adding it to the library) +2
- finishing a book (status 'read')           +5
- a lending record (lent or borrowed)        +3
"""

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Author, LendingRecord, LibraryEntry, Review, Work

POINTS = {
    "books_added": 10,
    "authors_added": 5,
    "reviews_written": 10,
    "books_tracked": 2,
    "books_finished": 5,
    "lending_records": 3,
}


async def _count(db: AsyncSession, model, *conditions) -> int:  # noqa: ANN001
    stmt = select(func.count()).select_from(model).where(*conditions)
    return int((await db.execute(stmt)).scalar_one())


async def compute_score(db: AsyncSession, user_id: uuid.UUID) -> dict[str, int]:
    """Return the per-category counts plus the weighted total."""
    counts = {
        "books_added": await _count(
            db, Work, Work.created_by_user_id == user_id, Work.deleted_at.is_(None)
        ),
        "authors_added": await _count(
            db, Author, Author.created_by_user_id == user_id, Author.deleted_at.is_(None)
        ),
        "reviews_written": await _count(
            db, Review, Review.user_id == user_id, Review.deleted_at.is_(None)
        ),
        "books_tracked": await _count(
            db, LibraryEntry, LibraryEntry.user_id == user_id, LibraryEntry.deleted_at.is_(None)
        ),
        "books_finished": await _count(
            db,
            LibraryEntry,
            LibraryEntry.user_id == user_id,
            LibraryEntry.status == "read",
            LibraryEntry.deleted_at.is_(None),
        ),
        "lending_records": await _count(
            db, LendingRecord, LendingRecord.user_id == user_id, LendingRecord.deleted_at.is_(None)
        ),
    }
    total = sum(counts[k] * POINTS[k] for k in POINTS)
    return {"total": total, **counts}
