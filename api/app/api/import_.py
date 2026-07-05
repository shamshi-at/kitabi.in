import csv
import io

from fastapi import APIRouter

from app.api.catalog import _summary
from app.api.deps import CurrentUser, DbSession
from app.schemas.catalog import ImportPreviewIn, ImportPreviewOut, ImportRowOut
from app.services import catalog_service, import_service

router = APIRouter(prefix="/import", tags=["import"])


@router.post("/preview", response_model=ImportPreviewOut)
async def preview(payload: ImportPreviewIn, user: CurrentUser, db: DbSession) -> ImportPreviewOut:
    """S2 — parse a Goodreads/generic CSV and match each row to the catalog
    (local, by ISBN then title). Read-only: the app creates the library entries
    itself on confirm (offline-first). Unmatched rows can be resolved by ISBN."""
    headers = next(csv.reader(io.StringIO(payload.csv)), [])
    fmt = "goodreads" if import_service.is_goodreads(headers) else "generic"

    rows = import_service.parse_csv(payload.csv)
    out_rows: list[ImportRowOut] = []
    matched = 0
    for row in rows:
        work = None
        if row.isbn:
            found = await catalog_service.search_local(db, row.isbn)
            work = found[0] if found else None
        if work is None:
            found = await catalog_service.search_local(db, row.title)
            work = found[0] if found else None
        if work is not None:
            matched += 1
        out_rows.append(
            ImportRowOut(
                title=row.title,
                author=row.author,
                isbn=row.isbn,
                rating=row.rating,
                review=row.review,
                status=row.status,
                date_read=row.date_read,
                tags=row.tags,
                match=_summary(work) if work is not None else None,
            )
        )

    return ImportPreviewOut(format=fmt, total=len(rows), matched=matched, rows=out_rows)
