"""Catalog operations — search (the same spelling-fold the app uses), a
quality-gap worklist, and the duplicate merge. Merge is the highest-risk action
in the console (it moves other readers' ratings/reviews and the editions their
library entries hang off), so it always previews what will move before it runs,
is editor+ only, and is audited. It reuses the API's merge_preview / merge_works.
"""

import uuid
from typing import Annotated

from app.services import buy_links as buy_links_service  # noqa: E402
from app.services import (
    catalog_service,  # noqa: E402
    merge_service,  # noqa: E402
)
from fastapi import APIRouter, Form, Query, Request, UploadFile
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse, Response
from sqlalchemy import Text, cast, func, or_, select
from sqlalchemy.orm import joinedload, selectinload

from .. import assets, queries, security
from ..deps import CurrentAdmin, DbSession, RequireEditor, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import (
    CLAIM_PENDING,
    Author,
    AuthorClaim,
    Edition,
    LibraryEntry,
    Profile,
    Publisher,
    Rating,
    Review,
    Series,
    Work,
)
from ..templating import templates
from .merges import _counts as _merge_counts

router = APIRouter(prefix="/catalog")


# ---------------------------------------------------------------------------
# Peek — "who is this, really?"
#
# Every merge decision is a question about identity, and a name plus a book
# count does not answer it: two Rev. William Benhams are told apart by what
# they wrote, not by how they are spelled. So any record anywhere in the
# console can be opened as a popup showing its catalog, without leaving the
# queue and losing the comparison you were in the middle of.
#
# Moderator-visible (not editor+) because the duplicate queue is, and every
# field here is already public on the website.
# ---------------------------------------------------------------------------

PEEK_MODELS = {
    "authors": Author,
    "publishers": Publisher,
    "works": Work,
    "series": Series,
}


def _fact(label: str, value) -> tuple | None:  # noqa: ANN001
    return (label, value) if value else None


async def _peek_author(db: DbSession, row: Author) -> dict:
    works = await catalog_service.author_works(db, row.id)
    linked = await db.get(Profile, row.linked_user_id) if row.linked_user_id else None
    return {
        "title": row.name,
        "sub": row.name_translit or "",
        "href": f"/catalog/authors/{row.id}",
        "image": row.image_url,
        "body": row.bio,
        "facts": [
            f
            for f in (
                _fact("Writes in", row.primary_language),
                _fact("Also known as", row.pen_name),
                _fact("Books in catalog", len(works)),
                _fact("Source", row.external_source or "reader-added"),
                _fact(
                    "On Kitabi",
                    (linked.full_name or linked.email) if linked else None,
                ),
            )
            if f
        ],
        "list_label": f"Books ({len(works)})",
        "entries": [
            {
                "href": f"/catalog/works/{w.id}",
                "title": w.title,
                "sub": " · ".join(
                    str(x) for x in (w.title_translit, w.first_publish_year, w.language) if x
                ),
            }
            for w in works
        ],
    }


async def _peek_publisher(db: DbSession, row: Publisher) -> dict:
    works = await catalog_service.publisher_works(db, row.id)
    editions = int(
        await db.scalar(
            select(func.count())
            .select_from(Edition)
            .where(Edition.publisher_id == row.id, Edition.deleted_at.is_(None))
        )
        or 0
    )
    return {
        "title": row.name,
        "sub": row.name_translit or "",
        "href": f"/catalog/publishers/{row.id}",
        "image": row.logo_url,
        "body": None,
        "facts": [
            f
            for f in (
                _fact("Publishes in", row.primary_language),
                _fact("Editions", editions),
                _fact("Works", len(works)),
                _fact("Source", row.external_source or "reader-added"),
            )
            if f
        ],
        "list_label": f"Works ({len(works)})",
        "entries": [
            {
                "href": f"/catalog/works/{w.id}",
                "title": w.title,
                "sub": " · ".join(str(x) for x in (w.title_translit, w.first_publish_year) if x),
            }
            for w in works
        ],
    }


async def _peek_series(db: DbSession, row: Series) -> dict:
    works = await catalog_service.series_works(db, row.id)
    return {
        "title": row.name,
        "sub": row.name_translit or "",
        "href": f"/catalog/series/{row.id}",
        "image": None,
        "body": row.description,
        "facts": [
            f
            for f in (
                _fact("Language", row.primary_language),
                _fact("Books", len(works)),
                _fact("Source", row.external_source or "reader-added"),
            )
            if f
        ],
        "list_label": f"Reading order ({len(works)})",
        "entries": [
            {
                "href": f"/catalog/works/{w.id}",
                "title": (f"{w.series_number}. " if w.series_number else "") + w.title,
                "sub": " · ".join(str(x) for x in (w.language, w.first_publish_year) if x),
            }
            for w in works
        ],
    }


async def _peek_work(db: DbSession, row: Work) -> dict:
    # Loaded here rather than through get_work_or_404, which 404s on a
    # soft-deleted work — peeking a row that was already merged away is exactly
    # when "what was this?" matters most.
    work = (
        (
            await db.execute(
                select(Work)
                .where(Work.id == row.id)
                .options(selectinload(Work.authors), selectinload(Work.editions))
            )
        )
        .unique()
        .scalar_one()
    )
    shelved = int(
        await db.scalar(
            select(func.count())
            .select_from(LibraryEntry)
            .where(
                LibraryEntry.edition_id.in_(select(Edition.id).where(Edition.work_id == row.id)),
                LibraryEntry.deleted_at.is_(None),
            )
        )
        or 0
    )
    ratings = int(
        await db.scalar(select(func.count()).select_from(Rating).where(Rating.work_id == row.id))
        or 0
    )
    reviews = int(
        await db.scalar(select(func.count()).select_from(Review).where(Review.work_id == row.id))
        or 0
    )
    cover = next((e.cover_url for e in work.editions if e.cover_url), None)
    return {
        "title": work.title,
        "sub": work.title_translit or "",
        "href": f"/catalog/works/{work.id}",
        "image": cover,
        "body": work.description,
        "facts": [
            f
            for f in (
                _fact("By", ", ".join(a.name for a in work.authors)),
                _fact("First published", work.first_publish_year),
                _fact("Language", work.language),
                _fact("Shelved by readers", shelved),
                _fact("Ratings / reviews", f"{ratings} / {reviews}"),
                _fact("Source", work.external_source or "reader-added"),
            )
            if f
        ],
        "list_label": f"Editions ({len(work.editions)})",
        "entries": [
            {
                "href": f"/catalog/works/{work.id}",
                "title": e.isbn or "no ISBN",
                "sub": " · ".join(
                    str(x)
                    for x in (
                        e.language,
                        e.publisher.name if e.publisher else None,
                        f"{e.page_count} pp" if e.page_count else None,
                    )
                    if x
                ),
            }
            for e in work.editions
        ],
    }


@router.get("/peek/{kind}/{row_id}")
async def peek(
    request: Request, admin: CurrentAdmin, db: DbSession, kind: str, row_id: uuid.UUID
) -> HTMLResponse:
    """One record's identity and its catalog, as a fragment for the popup."""
    row = await db.get(PEEK_MODELS[kind], row_id) if kind in PEEK_MODELS else None
    if row is None:
        return templates.TemplateResponse(
            request, "_peek.html", {"p": None, "kind": kind}, status_code=404
        )
    builder = {
        "authors": _peek_author,
        "publishers": _peek_publisher,
        "works": _peek_work,
        "series": _peek_series,
    }[kind]
    peeked = await builder(db, row)
    peeked.update(
        kind=kind,
        singular={
            "authors": "Author",
            "publishers": "Publisher",
            "works": "Work",
            "series": "Series",
        }[kind],
        id=str(row.id),
        merged_into=await merge_service.resolve_merged(db, kind, row) if kind != "works" else None,
        deleted=row.deleted_at is not None,
    )
    return templates.TemplateResponse(request, "_peek.html", {"p": peeked, "kind": kind})


@router.post("/rename")
async def rename(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    kind: Annotated[str, Form()],
    row_id: Annotated[uuid.UUID, Form()],
    name: Annotated[str, Form()],
    next_url: Annotated[str, Form(alias="next")] = "",
) -> RedirectResponse:
    """Fix a record's name (a work's title).

    The duplicate queue needs this: when a cluster is one entity under two bad
    spellings — "Rev. William Rev. William Benham" beside "Rev. William Benham"
    — neither row is the record to keep, and without a rename the reviewer can
    only choose which mistake becomes the public page.

    Renaming the row you keep beats creating a fresh one: the kept row already
    holds the books, the ratings and whatever ranking its URL earned, and the
    slug deliberately does not follow the name (services/slug_service), so the
    published URL keeps working.
    """
    back = next_url if next_url.startswith(("/catalog", "/moderation")) else "/catalog"
    resp = RedirectResponse(back, status_code=303)
    if kind not in PEEK_MODELS:
        set_flash(resp, "err", "Unknown kind.")
        return resp
    row = await db.get(PEEK_MODELS[kind], row_id)
    if row is None:
        set_flash(resp, "err", "Record not found.")
        return resp
    name = " ".join(name.split())  # collapse the whitespace a paste drags in
    if not name:
        set_flash(resp, "err", "A name can't be empty.")
        return resp

    attr = "title" if kind == "works" else "name"
    previous = getattr(row, attr)
    if previous == name:
        set_flash(resp, "ok", "That was already the name.")
        return resp
    setattr(row, attr, name)
    # name_translit / name_fold follow automatically (models/translit_hooks).
    await db.commit()
    await security.audit(
        db,
        "catalog.rename",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(row_id),
        summary=f"“{previous}” → “{name}”",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", f"Renamed to “{name}”. Its URL is unchanged.")
    return resp


async def _work_rows(db: DbSession, works: list) -> list[dict]:
    rows = []
    for w in works:
        editions = int(
            await db.scalar(
                select(func.count())
                .select_from(Edition)
                .where(Edition.work_id == w.id, Edition.deleted_at.is_(None))
            )
            or 0
        )
        shelved = int(
            await db.scalar(
                select(func.count())
                .select_from(LibraryEntry)
                .where(
                    LibraryEntry.edition_id.in_(select(Edition.id).where(Edition.work_id == w.id)),
                    LibraryEntry.deleted_at.is_(None),
                )
            )
            or 0
        )
        author = ", ".join(a.name for a in w.authors) if w.authors else "—"
        rows.append({"w": w, "author": author, "editions": editions, "shelved": shelved})
    return rows


# The quality-gap worklists the dashboard health bars and the catalog gap card
# both link into. Each key mirrors exactly the count shown on the cards, so the
# worklist a click opens matches the number the reader clicked.
GAP_LABELS = {
    "no_cover": "Editions with no cover",
    "no_desc": "Works with no description",
    "no_isbn": "Editions with no ISBN",
}


def _gap_stmt(gap: str):  # noqa: ANN201 — SQLAlchemy Select
    base = select(Work).options(selectinload(Work.authors)).where(Work.deleted_at.is_(None))
    if gap == "no_desc":
        return base.where(Work.description.is_(None))
    if gap == "no_cover":
        return base.where(
            Work.id.in_(
                select(Edition.work_id).where(
                    Edition.deleted_at.is_(None), Edition.cover_url.is_(None)
                )
            )
        )
    if gap == "no_isbn":
        return base.where(
            Work.id.in_(
                select(Edition.work_id).where(Edition.deleted_at.is_(None), Edition.isbn.is_(None))
            )
        )
    return None


async def _adder_name(db: DbSession, user_id: uuid.UUID) -> str:
    p = await db.get(Profile, user_id)
    return (p.full_name or p.email) if p else str(user_id)[:8]


@router.get("")
async def catalog(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    q: str = Query(default=""),
    gap: str = Query(default="", alias="filter"),
    added_by: Annotated[uuid.UUID | None, Query()] = None,
    keep: Annotated[uuid.UUID | None, Query()] = None,
) -> HTMLResponse:
    q = q.strip()
    filter_label = None
    if added_by is not None:
        works = list(
            (
                await db.execute(
                    select(Work)
                    .options(selectinload(Work.authors))
                    .where(Work.created_by_user_id == added_by, Work.deleted_at.is_(None))
                    .order_by(Work.title.asc())
                    .limit(300)
                )
            )
            .scalars()
            .all()
        )
        filter_label = f"Works added by {await _adder_name(db, added_by)}"
    elif gap in GAP_LABELS:
        works = list(
            (await db.execute(_gap_stmt(gap).order_by(Work.title.asc()).limit(300))).scalars().all()
        )
        filter_label = GAP_LABELS[gap]
    else:
        works = await catalog_service.search_local(db, q) if q else []
    rows = await _work_rows(db, works)

    # Quality gaps — the columns a bulk seed leaves thin.
    async def count(model, *cond):  # noqa: ANN001
        return int(await db.scalar(select(func.count()).select_from(model).where(*cond)) or 0)

    gaps = {
        "no_cover": await count(Edition, Edition.deleted_at.is_(None), Edition.cover_url.is_(None)),
        "no_desc": await count(Work, Work.deleted_at.is_(None), Work.description.is_(None)),
        "no_isbn": await count(Edition, Edition.deleted_at.is_(None), Edition.isbn.is_(None)),
        "no_amazon": await count(Edition, Edition.deleted_at.is_(None), _no_stored_amazon()),
        "no_works_author": await count(
            Author,
            Author.deleted_at.is_(None),
            ~Author.id.in_(select(func.distinct(catalog_service.work_authors.c.author_id))),
        ),
    }
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "catalog.html",
        {
            "admin": admin,
            "active": "catalog",
            "badges": badges,
            "q": q,
            "rows": rows,
            "gaps": gaps,
            "gap": gap,
            "added_by": added_by,
            "keep": keep,
            "filter_label": filter_label,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.get("/works/{work_id}")
async def book_detail(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    work_id: uuid.UUID,
    series_q: str = Query(default=""),
) -> HTMLResponse:
    try:
        work = await catalog_service.get_work_or_404(db, work_id)
    except Exception:  # noqa: BLE001
        resp = RedirectResponse("/catalog", status_code=303)
        set_flash(resp, "err", "Work not found.")
        return resp
    # The stored Amazon link per edition (first Amazon-family entry in the
    # buy_links JSONB) — prefills the curation field. Editions without one
    # get the read-time generated link, so an empty field is normal, not a gap.
    amazon_links = {
        e.id: next(
            (
                str(link["url"])
                for link in (e.buy_links or [])
                if isinstance(link, dict) and buy_links_service.is_amazon(str(link.get("url", "")))
            ),
            "",
        )
        for e in work.editions
    }
    ratings = int(
        await db.scalar(select(func.count()).select_from(Rating).where(Rating.work_id == work_id))
        or 0
    )
    reviews = int(
        await db.scalar(select(func.count()).select_from(Review).where(Review.work_id == work_id))
        or 0
    )
    shelved = int(
        await db.scalar(
            select(func.count())
            .select_from(LibraryEntry)
            .where(
                LibraryEntry.edition_id.in_(select(Edition.id).where(Edition.work_id == work_id))
            )
        )
        or 0
    )
    series_q = series_q.strip()
    series_matches = await catalog_service.search_series(db, series_q, limit=8) if series_q else []
    series_counts = await catalog_service.series_book_counts(db, [s.id for s in series_matches])
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "book_detail.html",
        {
            "admin": admin,
            "active": "catalog",
            "badges": badges,
            "w": work,
            "ratings": ratings,
            "reviews": reviews,
            "shelved": shelved,
            "amazon_links": amazon_links,
            "series_q": series_q,
            "series_matches": [
                {"s": s, "count": series_counts.get(s.id, 0)} for s in series_matches
            ],
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


def _no_stored_amazon():  # noqa: ANN202 — SQLAlchemy boolean expression
    """Editions with no hand-entered Amazon-family link in buy_links. A text
    scan of the JSONB, deliberately broader than buy_links.is_amazon — a false
    "has one" hides a row from the worklist, a false "missing" just shows a row
    whose generated link already works, so broad is the safe direction."""
    txt = func.coalesce(cast(Edition.buy_links, Text), "")
    return txt.notilike("%amazon%") & txt.notilike("%amzn%")


_BL_PER_PAGE = 50


@router.get("/buy-links")
async def buy_links_worklist(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    q: str = Query(default=""),
    lang: str = Query(default=""),
    page: int = Query(default=1, ge=1),
) -> HTMLResponse:
    """The bulk curation table: every edition still missing a stored Amazon
    link, one row per edition (a translation is its own edition, so each
    language gets its own link), with the amazon.in search open-in-new-tab so
    the loop is search → copy → paste → save, never retype."""
    q, lang = q.strip(), lang.strip()
    cond = [Edition.deleted_at.is_(None), Work.deleted_at.is_(None), _no_stored_amazon()]
    if q:
        like = f"%{q}%"
        cond.append(or_(Work.title.ilike(like), Work.title_translit.ilike(like)))

    # Language facets, counted before the language filter is applied so the
    # other options stay visible (and pickable) while one is active. One
    # expression object reused in SELECT and GROUP BY — two separately-built
    # coalesce() calls bind as two different parameters and Postgres rejects
    # the GROUP BY as not matching.
    lang_col = func.coalesce(Edition.language, "")
    lang_rows = (
        await db.execute(
            select(lang_col, func.count())
            .select_from(Edition)
            .join(Work, Edition.work_id == Work.id)
            .where(*cond)
            .group_by(lang_col)
            .order_by(func.count().desc())
        )
    ).all()

    if lang:
        cond.append(func.coalesce(Edition.language, "") == ("" if lang == "none" else lang))

    total = int(
        await db.scalar(
            select(func.count())
            .select_from(Edition)
            .join(Work, Edition.work_id == Work.id)
            .where(*cond)
        )
        or 0
    )
    editions = (
        (
            await db.execute(
                select(Edition)
                .join(Work, Edition.work_id == Work.id)
                .where(*cond)
                .options(joinedload(Edition.work).selectinload(Work.authors))
                .order_by(Work.title.asc(), Edition.id)
                .limit(_BL_PER_PAGE)
                .offset((page - 1) * _BL_PER_PAGE)
            )
        )
        .scalars()
        .all()
    )
    rows = [
        {
            "e": e,
            "w": e.work,
            "author": ", ".join(a.name for a in e.work.authors) if e.work.authors else "",
            "search": buy_links_service.search_url(
                e.isbn, e.work.title, e.work.authors[0].name if e.work.authors else None
            ),
        }
        for e in editions
    ]
    here = request.url.path + (f"?{request.url.query}" if request.url.query else "")
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "buy_links.html",
        {
            "admin": admin,
            "active": "buylinks",
            "badges": badges,
            "rows": rows,
            "total": total,
            "page": page,
            "pages": max(1, -(-total // _BL_PER_PAGE)),
            "q": q,
            "lang": lang,
            "langs": [
                {"value": value or "none", "label": value or "(not set)", "count": count_}
                for value, count_ in lang_rows
            ],
            "here": here,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/works/{work_id}/series")
async def set_work_series(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    work_id: uuid.UUID,
    series_id: Annotated[str, Form()] = "",
    series_name: Annotated[str, Form()] = "",
    number: Annotated[str, Form()] = "",
) -> RedirectResponse:
    """Set (or clear) a book's series from its own page — the other direction
    of the same act as adding it from the series page. An empty `series_id`
    with an empty name takes it out."""
    resp = RedirectResponse(f"/catalog/works/{work_id}", status_code=303)
    work = await db.get(Work, work_id)
    if work is None or work.deleted_at is not None:
        set_flash(resp, "err", "Work not found.")
        return resp
    series = None
    if series_id.strip():
        try:
            series = await db.get(Series, uuid.UUID(series_id.strip()))
        except ValueError:
            series = None
    elif series_name.strip():
        series = await catalog_service.create_series(db, name=series_name.strip())
    position = int(number) if number.strip().isdigit() else None
    shared = await catalog_service.set_work_series(db, work, series, position)
    await db.commit()
    await security.audit(
        db,
        "series.set" if series else "series.clear",
        admin_id=admin.id,
        target_type="work",
        target_id=str(work_id),
        summary=(
            (f"{work.title} → {series.name}" + (f" #{position}" if position else ""))
            if series
            else f"{work.title} taken out of its series"
        ),
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(
        resp,
        "ok",
        (f"Series set to “{series.name}”." if series else "Series cleared.")
        + (f" {shared} translation(s) took the same position." if shared else ""),
    )
    return resp


@router.post("/works/{work_id}/editions/{edition_id}/amazon-link")
async def set_edition_amazon_link(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    work_id: uuid.UUID,
    edition_id: uuid.UUID,
    url: Annotated[str, Form()] = "",
    next_url: Annotated[str, Form(alias="next")] = "",
) -> Response:
    """Curate the edition's Amazon link. A stored link wins over the read-time
    generated one (services/buy_links.py), so this is the override for the
    books where the ISBN-derived link lands wrong — everything else keeps the
    dynamic link. An empty submit clears the override; other stored retailers
    in the JSONB are preserved either way.

    Serves two callers: the book page (plain form → redirect + flash) and the
    buy-links worklist (fetch → bare status, the row marks itself saved without
    a reload). `next` sends the non-JS fallback back to the worklist; it must
    be a console-local path or it is ignored, so it can't become a redirector."""
    is_fetch = request.headers.get("x-requested-with") == "fetch"
    back = next_url if next_url.startswith("/catalog") else f"/catalog/works/{work_id}"

    def fail(message: str) -> Response:
        if is_fetch:
            return PlainTextResponse(message, status_code=400)
        r = RedirectResponse(back, status_code=303)
        set_flash(r, "err", message)
        return r

    edition = await db.get(Edition, edition_id)
    if edition is None or edition.work_id != work_id or edition.deleted_at is not None:
        return fail("Edition not found on this work.")
    url = url.strip()
    if url and not buy_links_service.is_amazon(url):
        return fail("That doesn't look like an Amazon link (amazon.in / amzn.to).")

    kept = [
        link
        for link in (edition.buy_links or [])
        if isinstance(link, dict)
        and link.get("url")
        and not buy_links_service.is_amazon(str(link["url"]))
    ]
    # Reassigned, never mutated in place — a JSONB column only registers a
    # change when the attribute is set to a new object.
    edition.buy_links = ([{"retailer": "Amazon", "url": url}] if url else []) + kept or None
    await db.commit()
    await security.audit(
        db,
        "catalog.amazon_link.set" if url else "catalog.amazon_link.clear",
        admin_id=admin.id,
        target_type="edition",
        target_id=str(edition_id),
        summary=(f"Amazon link → {url}" if url else "Amazon link cleared")
        + f" (edition {edition.isbn or 'no ISBN'})",
        ip=client_ip(request),
    )
    await db.commit()
    if is_fetch:
        return Response(status_code=204)
    resp = RedirectResponse(back, status_code=303)
    set_flash(
        resp,
        "ok",
        "Amazon link saved." if url else "Amazon link cleared — back to the generated one.",
    )
    return resp


@router.get("/authors")
async def authors(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    q: str = Query(default=""),
    gap: str = Query(default="", alias="filter"),
    added_by: Annotated[uuid.UUID | None, Query()] = None,
) -> HTMLResponse:
    q = q.strip()
    filter_label = None
    if added_by is not None:
        rows = list(
            (
                await db.execute(
                    select(Author)
                    .where(Author.created_by_user_id == added_by, Author.deleted_at.is_(None))
                    .order_by(Author.name.asc())
                    .limit(300)
                )
            )
            .scalars()
            .all()
        )
        filter_label = f"Authors added by {await _adder_name(db, added_by)}"
    elif gap == "no_works":
        rows = list(
            (
                await db.execute(
                    select(Author)
                    .where(
                        Author.deleted_at.is_(None),
                        ~Author.id.in_(
                            select(func.distinct(catalog_service.work_authors.c.author_id))
                        ),
                    )
                    .order_by(Author.name.asc())
                    .limit(300)
                )
            )
            .scalars()
            .all()
        )
        filter_label = "Authors with no works"
    elif q:
        rows = await catalog_service.search_authors(db, q, limit=100)
    else:
        rows = await catalog_service.browse_authors(db, 60, 0, popular=True)
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "authors.html",
        {
            "admin": admin,
            "active": "authors",
            "badges": badges,
            "q": q,
            "rows": rows,
            "filter_label": filter_label,
        },
    )


# The manual side of duplicate handling. The matchers propose what they can
# (moderation/merges), but a cross-script duplicate — "ഡിസി ബുക്സ്" beside
# "DC Books" — shares no spelling with its twin, so no matcher will ever offer
# it. The detail pages let a human search for the true record (search IS
# cross-script) and link the two by hand.


async def _merge_candidates(
    db: DbSession, kind: str, current_id: uuid.UUID, merge_q: str
) -> list[dict]:
    """Rows the current entity could be folded into (or absorb), with how much
    each carries — the reviewer needs the counts to pick the right survivor."""
    if not merge_q:
        return []
    search = {
        "authors": catalog_service.search_authors,
        "publishers": catalog_service.search_publishers,
        "series": catalog_service.search_series,
    }[kind]
    found = await search(db, merge_q, limit=8)
    rows = [r for r in found if r.id != current_id and r.merged_into_id is None]
    counts = await _merge_counts(db, kind, [r.id for r in rows])
    return [{"r": r, "count": counts.get(r.id, 0)} for r in rows]


@router.post("/entity-merge")
async def entity_merge(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    kind: Annotated[str, Form()],
    survivor_id: Annotated[uuid.UUID, Form()],
    loser_id: Annotated[uuid.UUID, Form()],
) -> RedirectResponse:
    """Fold one author/publisher into another, picked by hand on a detail page.
    Same engine and same guards as the moderation queue (merge_service); the
    queue handles what the matchers propose, this handles what they can't see."""
    if kind not in merge_service.MODELS:
        resp = RedirectResponse("/catalog", status_code=303)
        set_flash(resp, "err", "Unknown kind.")
        return resp
    resp = RedirectResponse(f"/catalog/{kind}/{survivor_id}", status_code=303)
    model = merge_service.MODELS[kind]
    loser = await db.get(model, loser_id)
    loser_name = loser.name if loser else "?"
    if not await merge_service.merge(db, kind, survivor_id, loser_id):
        back = RedirectResponse(f"/catalog/{kind}/{loser_id}", status_code=303)
        set_flash(back, "err", "Could not merge those — one may already be merged.")
        return back
    await db.commit()
    survivor = await db.get(model, survivor_id)
    await security.audit(
        db,
        "merge.apply",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(survivor_id),
        summary=f"merged “{loser_name}” into “{survivor.name if survivor else '?'}” (manual)",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", f"Merged “{loser_name}” in. Its old URL redirects here now.")
    return resp


@router.post("/entity-unmerge")
async def entity_unmerge(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    kind: Annotated[str, Form()],
    row_id: Annotated[uuid.UUID, Form()],
) -> RedirectResponse:
    resp = RedirectResponse(f"/catalog/{kind}/{row_id}", status_code=303)
    if kind not in merge_service.MODELS or not await merge_service.unmerge(db, kind, row_id):
        set_flash(resp, "err", "That row is not merged.")
        return resp
    await db.commit()
    await security.audit(
        db,
        "merge.undo",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(row_id),
        summary="unmerged (works stay with the survivor)",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", "Unmerged. Its books stayed with the survivor — move them by hand.")
    return resp


@router.get("/authors/{author_id}")
async def author_detail(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    author_id: uuid.UUID,
    merge_q: str = Query(default=""),
) -> HTMLResponse:
    author = await db.get(Author, author_id)
    if author is None:
        resp = RedirectResponse("/catalog/authors", status_code=303)
        set_flash(resp, "err", "Author not found.")
        return resp
    works = await catalog_service.author_works(db, author_id)
    linked = None
    if author.linked_user_id is not None:
        linked = await db.get(Profile, author.linked_user_id)
    pending_claims = int(
        await db.scalar(
            select(func.count())
            .select_from(AuthorClaim)
            .where(AuthorClaim.author_id == author_id, AuthorClaim.status == CLAIM_PENDING)
        )
        or 0
    )
    merge_q = merge_q.strip()
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "author_detail.html",
        {
            "admin": admin,
            "active": "authors",
            "badges": badges,
            "a": author,
            "works": works,
            "linked": linked,
            "pending_claims": pending_claims,
            "kind": "authors",
            "merge_q": merge_q,
            "merge_candidates": await _merge_candidates(db, "authors", author_id, merge_q),
            "merged_into": await merge_service.resolve_merged(db, "authors", author),
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.get("/series")
async def series_list(
    request: Request, admin: RequireEditor, db: DbSession, q: str = Query(default="")
) -> HTMLResponse:
    """Every series with what it holds. The empty ones are shown, not hidden:
    a series with no books is the residue of a typo in the old free-text field,
    and finding them is the point of the screen."""
    q = q.strip()
    if q:
        found = await catalog_service.search_series(db, q, limit=100)
        counts = await catalog_service.series_book_counts(db, [s.id for s in found])
        rows = [(s, counts.get(s.id, 0)) for s in found]
    else:
        rows = await catalog_service.browse_series(db, 200, 0, popular=True)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "series.html",
        {
            "admin": admin,
            "active": "series",
            "badges": badges,
            "q": q,
            "rows": [{"s": s, "count": count} for s, count in rows],
            "empty_count": sum(1 for _, count in rows if not count),
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.get("/series/{series_id}")
async def series_detail(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    series_id: uuid.UUID,
    merge_q: str = Query(default=""),
    add_q: str = Query(default=""),
) -> HTMLResponse:
    series = await db.get(Series, series_id)
    if series is None:
        resp = RedirectResponse("/catalog/series", status_code=303)
        set_flash(resp, "err", "Series not found.")
        return resp
    works = await catalog_service.series_works(db, series_id)
    # Candidates to add: a title search, minus what is already in the series.
    add_q = add_q.strip()
    in_series = {w.id for w in works}
    candidates = [
        w
        for w in (await catalog_service.search_local(db, add_q) if add_q else [])
        if w.id not in in_series
    ]
    merge_q = merge_q.strip()
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "series_detail.html",
        {
            "admin": admin,
            "active": "series",
            "badges": badges,
            "s": series,
            "works": works,
            "add_q": add_q,
            "candidates": candidates,
            "kind": "series",
            "merge_q": merge_q,
            "merge_candidates": await _merge_candidates(db, "series", series_id, merge_q),
            "merged_into": await merge_service.resolve_merged(db, "series", series),
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/series/{series_id}/works")
async def series_add_work(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    series_id: uuid.UUID,
    work_id: Annotated[uuid.UUID, Form()],
    number: Annotated[str, Form()] = "",
) -> RedirectResponse:
    """Put a book in the series at a position. Goes through the service, so
    every translation of that book lands at the same position too."""
    resp = RedirectResponse(f"/catalog/series/{series_id}", status_code=303)
    series = await db.get(Series, series_id)
    work = await db.get(Work, work_id)
    if series is None or work is None or work.deleted_at is not None:
        set_flash(resp, "err", "Series or book not found.")
        return resp
    position = int(number) if number.strip().isdigit() else None
    shared = await catalog_service.set_work_series(db, work, series, position)
    await db.commit()
    await security.audit(
        db,
        "series.add_work",
        admin_id=admin.id,
        target_type="series",
        target_id=str(series_id),
        summary=f"“{work.title}” → {series.name}" + (f" #{position}" if position else ""),
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(
        resp,
        "ok",
        f"Added “{work.title}”."
        + (f" {shared} translation(s) took the same position." if shared else ""),
    )
    return resp


@router.post("/series/{series_id}/works/{work_id}/remove")
async def series_remove_work(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    series_id: uuid.UUID,
    work_id: uuid.UUID,
) -> RedirectResponse:
    resp = RedirectResponse(f"/catalog/series/{series_id}", status_code=303)
    work = await db.get(Work, work_id)
    if work is None or work.series_id != series_id:
        set_flash(resp, "err", "That book isn't in this series.")
        return resp
    # propagate=False: taking one book out is not a statement about its
    # translations, and silently emptying the series in three other languages
    # is not what "remove" looks like to anyone.
    await catalog_service.set_work_series(db, work, None, None, propagate=False)
    await db.commit()
    await security.audit(
        db,
        "series.remove_work",
        admin_id=admin.id,
        target_type="series",
        target_id=str(series_id),
        summary=f"removed “{work.title}”",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", f"Removed “{work.title}” from the series.")
    return resp


@router.get("/publishers")
async def publishers(
    request: Request, admin: RequireEditor, db: DbSession, q: str = Query(default="")
) -> HTMLResponse:
    q = q.strip()
    rows = (
        await catalog_service.search_publishers(db, q, limit=100)
        if q
        else await catalog_service.browse_publishers(db, 60, 0, popular=True)
    )
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "publishers.html",
        {"admin": admin, "active": "publishers", "badges": badges, "q": q, "rows": rows},
    )


@router.get("/publishers/{publisher_id}")
async def publisher_detail(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    publisher_id: uuid.UUID,
    merge_q: str = Query(default=""),
) -> HTMLResponse:
    publisher = await db.get(Publisher, publisher_id)
    if publisher is None:
        resp = RedirectResponse("/catalog/publishers", status_code=303)
        set_flash(resp, "err", "Publisher not found.")
        return resp
    works = await catalog_service.publisher_works(db, publisher_id)
    merge_q = merge_q.strip()
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "publisher_detail.html",
        {
            "admin": admin,
            "active": "publishers",
            "badges": badges,
            "p": publisher,
            "works": works,
            "uploads_on": assets.configured(),
            "uploads_why": assets.why_not_configured(),
            "kind": "publishers",
            "merge_q": merge_q,
            "merge_candidates": await _merge_candidates(db, "publishers", publisher_id, merge_q),
            "merged_into": await merge_service.resolve_merged(db, "publishers", publisher),
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/publishers/{publisher_id}/logo/remove")
async def remove_publisher_logo(
    request: Request, admin: RequireEditor, db: DbSession, publisher_id: uuid.UUID
) -> RedirectResponse:
    """Take a logo back off.

    Without this the page could only ever *add* one, so a wrong upload was
    permanent from the console (owner report, 31 Jul 2026). The stored object
    stays in the bucket — the URL is in the audit trail, so a mistake is
    recoverable by pasting it back rather than by hunting for the file.
    """
    resp = RedirectResponse(f"/catalog/publishers/{publisher_id}", status_code=303)
    publisher = await db.get(Publisher, publisher_id)
    if publisher is None:
        set_flash(resp, "err", "Publisher not found.")
        return resp
    if not publisher.logo_url:
        set_flash(resp, "err", "There was no logo to remove.")
        return resp
    previous, publisher.logo_url = publisher.logo_url, None
    await db.commit()
    await security.audit(
        db,
        "publisher.remove_logo",
        admin_id=admin.id,
        target_type="publisher",
        target_id=publisher_id,
        summary=f"{publisher.name} · was {previous}",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", f"Logo removed from {publisher.name}.")
    return resp


@router.post("/publishers/{publisher_id}/logo")
async def upload_publisher_logo(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    publisher_id: uuid.UUID,
    logo: UploadFile | None = None,
) -> RedirectResponse:
    """Give a publisher a logo.

    Nothing upstream supplies these — OpenLibrary has no publisher art, so every
    `logo_url` in the catalog is null (owner request, 31 Jul 2026). The app can
    already set one from the publisher picker; this is the same thing from the
    operator's side, writing to the same `covers` bucket under the same
    `publishers/` prefix, so the two can't drift apart.
    """
    resp = RedirectResponse(f"/catalog/publishers/{publisher_id}", status_code=303)
    publisher = await db.get(Publisher, publisher_id)
    if publisher is None:
        set_flash(resp, "err", "Publisher not found.")
        return resp
    if logo is None or not logo.filename:
        set_flash(resp, "err", "No file chosen.")
        return resp
    try:
        publisher.logo_url = await assets.upload_image(
            "publishers", logo.filename, await logo.read(), logo.content_type
        )
    except assets.UploadError as exc:
        set_flash(resp, "err", str(exc))
        return resp
    await db.commit()
    await security.audit(
        db,
        "publisher.upload_logo",
        admin_id=admin.id,
        target_type="publisher",
        target_id=publisher_id,
        summary=publisher.name,
        ip=client_ip(request),
    )
    set_flash(resp, "ok", f"Logo saved for {publisher.name}.")
    return resp


@router.get("/merge")
async def merge_preview(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    keep: Annotated[uuid.UUID, Query()],
    absorb: Annotated[uuid.UUID, Query()],
) -> HTMLResponse:
    badges = await queries.nav_badges(db)
    try:
        preview = await catalog_service.merge_preview(db, keep, absorb)
    except Exception as exc:  # noqa: BLE001
        resp = RedirectResponse("/catalog", status_code=303)
        set_flash(
            resp, "err", (getattr(exc, "detail", {}) or {}).get("message", "Cannot merge those.")
        )
        return resp
    return templates.TemplateResponse(
        request,
        "merge.html",
        {
            "admin": admin,
            "active": "catalog",
            "badges": badges,
            "p": preview,
            "keep": keep,
            "absorb": absorb,
        },
    )


@router.post("/merge")
async def merge_execute(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    keep: Annotated[uuid.UUID, Form()],
    absorb: Annotated[uuid.UUID, Form()],
    confirm: Annotated[str, Form()] = "",
) -> RedirectResponse:
    resp = RedirectResponse("/catalog", status_code=303)
    if confirm != "MERGE":
        set_flash(resp, "err", "Merge not confirmed.")
        return resp
    try:
        result = await catalog_service.merge_works(db, keep, absorb)
    except Exception as exc:  # noqa: BLE001
        set_flash(resp, "err", (getattr(exc, "detail", {}) or {}).get("message", "Merge failed."))
        return resp
    await security.audit(
        db,
        "work.merge",
        admin_id=admin.id,
        target_type="work",
        target_id=str(keep),
        summary=f"{result['absorbed_title']} → {result['keep_title']}",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", f"Merged “{result['absorbed_title']}” into “{result['keep_title']}”.")
    return resp
