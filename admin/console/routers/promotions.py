"""Campaigns — create, target, schedule and stop the in-app banner and card
(docs/promotions-plan.md §8).

Editor and above, not moderator: a moderator handles reports; publishing to
every reader's Home is an editor's job. Every mutation writes an audit row —
this is exactly the kind of action that should be impossible to do quietly.

The composer is four tabs over one campaign, each its own small form, so
switching tabs can never silently drop what you typed on another.
"""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated

from app.models.promotion import (
    ACTIONS,
    CARD_STYLES,
    KIND_BANNER,
    KIND_CARD,
    KINDS,
    PLACEMENT_HOME_STREAM,
    PLACEMENT_HOME_TOP,
    PLACEMENTS,
    STATUS_DRAFT,
    STATUS_PAUSED,
    STATUS_PUBLISHED,
)
from app.services import catalog_service, promotion_service
from fastapi import APIRouter, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import delete, func, select

from .. import assets, queries, security
from ..deps import DbSession, RequireEditor, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import (
    Author,
    Edition,
    Promotion,
    PromotionContent,
    PromotionEvent,
    Publisher,
    Work,
)
from ..templating import templates

router = APIRouter(prefix="/promotions")

# Dates are typed in IST and stored UTC (CLAUDE.md rule 5). Fixed offset rather
# than a tz database lookup: India has no DST, and this is the only place in the
# console that converts.
IST = timedelta(hours=5, minutes=30)

# Offered in the language-variant picker. Mirrors app/lib/core/languages.dart's
# India shelf — the wider world is available by typing, but these are the ones a
# campaign realistically targets.
COMMON_LANGUAGES = [
    "Malayalam",
    "English",
    "Hindi",
    "Tamil",
    "Kannada",
    "Telugu",
    "Marathi",
    "Bengali",
]

STATUS_ORDER = ["live", "scheduled", "paused", "draft", "ended"]


def _to_utc(local: str | None) -> datetime | None:
    """'2026-08-09T23:59' as typed in IST -> aware UTC."""
    if not local:
        return None
    try:
        naive = datetime.fromisoformat(local)
    except ValueError:
        return None
    return (naive - IST).replace(tzinfo=UTC)


def _to_ist_field(value: datetime | None) -> str:
    """Aware UTC -> the string a datetime-local input wants, in IST."""
    if value is None:
        return ""
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return (value.astimezone(UTC) + IST).strftime("%Y-%m-%dT%H:%M")


def _csv(raw: str | None) -> list[str]:
    return [part.strip() for part in (raw or "").split(",") if part.strip()]


def _int_or_none(raw: str | None) -> int | None:
    try:
        return int(raw) if raw not in (None, "") else None
    except ValueError:
        return None


async def _render(request: Request, admin, db: DbSession, name: str, ctx: dict) -> HTMLResponse:
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        name,
        {
            "admin": admin,
            "active": "promotions",
            "badges": await queries.nav_badges(db),
            "flash": flash,
            **ctx,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


async def _get_or_404(db: DbSession, promotion_id: uuid.UUID) -> Promotion:
    promo = await db.get(Promotion, promotion_id)
    if promo is None or promo.deleted_at is not None:
        raise HTTPException(status_code=404)
    return promo


async def _contents(db: DbSession, promotion_id: uuid.UUID) -> list[PromotionContent]:
    rows = (
        (
            await db.execute(
                select(PromotionContent).where(PromotionContent.promotion_id == promotion_id)
            )
        )
        .scalars()
        .all()
    )
    # Default first, then languages alphabetically — a stable order so the tab
    # strip doesn't reshuffle itself between saves.
    return sorted(rows, key=lambda c: (c.language is not None, c.language or ""))


async def _stats(db: DbSession, promotion_ids: list[uuid.UUID]) -> dict[uuid.UUID, dict]:
    """Impressions / unique readers / clicks / dismisses per campaign."""
    if not promotion_ids:
        return {}
    rows = (
        await db.execute(
            select(
                PromotionEvent.promotion_id,
                PromotionEvent.kind,
                func.count(),
                func.count(func.distinct(PromotionEvent.user_id)),
            )
            .where(PromotionEvent.promotion_id.in_(promotion_ids))
            .group_by(PromotionEvent.promotion_id, PromotionEvent.kind)
        )
    ).all()
    out: dict[uuid.UUID, dict] = {
        pid: {"impressions": 0, "readers": 0, "clicks": 0, "dismisses": 0} for pid in promotion_ids
    }
    for promotion_id, kind, count, readers in rows:
        bucket = out[promotion_id]
        if kind == "impression":
            bucket["impressions"], bucket["readers"] = count, readers
        elif kind == "click":
            bucket["clicks"] = count
        elif kind == "dismiss":
            bucket["dismisses"] = count
    for bucket in out.values():
        seen = bucket["impressions"] or 0
        bucket["ctr"] = round(100 * bucket["clicks"] / seen, 1) if seen else None
        bucket["dismiss_rate"] = round(100 * bucket["dismisses"] / seen, 1) if seen else None
    return out


def _audience_summary(targeting: dict) -> str:
    """The targeting rules in words. A rule you have to decode is a rule you
    will get wrong — so the list never shows raw JSON."""
    t = targeting or {}
    parts: list[str] = []
    if languages := t.get("languages"):
        parts.append(" & ".join(languages) + " readers")
    else:
        parts.append("Everyone")
    if platforms := t.get("platform"):
        parts.append("on " + " + ".join(p.title() for p in platforms))
    if ids := t.get("reader_ids"):
        parts.append(f"{len(ids)} named reader{'s' if len(ids) != 1 else ''} only")
    if size := t.get("library_size"):
        if size.get("min"):
            parts.append(f"{size['min']}+ books")
        if size.get("max") is not None:
            parts.append(f"≤{size['max']} books")
    if age := t.get("account_age_days"):
        if age.get("max") is not None:
            parts.append(f"joined < {age['max']}d ago")
        if age.get("min"):
            parts.append(f"joined > {age['min']}d ago")
    if statuses := t.get("has_status"):
        parts.append("with a book " + "/".join(statuses))
    if genres := t.get("genres"):
        parts.append("reading " + "/".join(genres))
    if (rollout := t.get("rollout_percent")) not in (None, 100):
        parts.append(f"{rollout}% rollout")
    return " · ".join(parts)


def _subject_id(promo: Promotion):
    """Whichever catalog thing this campaign features, if any."""
    return promo.work_id or promo.author_id or promo.publisher_id


def _subject_kind(promo: Promotion) -> str:
    if promo.author_id:
        return "author"
    if promo.publisher_id:
        return "publisher"
    return "book"


def _blockers(promo: Promotion, contents: list[PromotionContent]) -> list[str]:
    """What still stands between this campaign and a reader's Home."""
    out: list[str] = []
    if not contents:
        out.append("No copy written yet")
    elif not any(c.language is None for c in contents):
        out.append("No default copy — readers outside your languages would see nothing")
    if promo.kind == KIND_CARD and not promo.card_style:
        out.append("No card style chosen")
    if promo.kind == KIND_CARD and promo.card_style == "book" and not _subject_id(promo):
        out.append("Book-led card with nothing featured — pick a book, author or publisher")
    if not promo.starts_at:
        out.append("No start date")
    if not promo.ends_at and not promo.open_ended:
        # An open-ended promotion is the one that gets forgotten, so a missing
        # end date does block — but only while nobody has *decided*. Ticking
        # "runs until I stop it" is that decision, and this must then stop
        # firing (owner report, 31 Jul 2026: the checklist demanded an end date
        # while the box was already ticked).
        out.append("No end date — set one, or tick 'runs until I stop it'")
    return out


def _notes(promo: Promotion, contents: list[PromotionContent]) -> list[str]:
    """Worth knowing before publishing, but not wrong — so these never gate.

    A targeted language with no variant of its own is the *designed* fallback,
    not a fault: the default variant exists precisely so those readers still
    get something. It used to sit in the blocker list and gate Publish, which
    made a perfectly ordinary campaign unpublishable (owner report, 31 Jul
    2026). A checklist that cries wolf gets read as decoration.
    """
    out: list[str] = []
    for language in (promo.targeting or {}).get("languages", []):
        if not any(c.language == language for c in contents):
            out.append(f"{language} readers see the default copy — no {language} variant yet")
    if promo.open_ended:
        out.append("Runs until you stop it — no end date")
    if (promo.frequency or {}).get("dismissible") is False:
        out.append("Readers cannot dismiss this")
    return out


# --------------------------------------------------------------------------
# List
# --------------------------------------------------------------------------


@router.get("")
async def index(request: Request, admin: RequireEditor, db: DbSession) -> HTMLResponse:
    now = datetime.now(UTC)
    promos = (
        (
            await db.execute(
                select(Promotion)
                .where(Promotion.deleted_at.is_(None))
                .order_by(Promotion.created_at.desc())
            )
        )
        .scalars()
        .all()
    )
    stats = await _stats(db, [p.id for p in promos])
    grouped: dict[str, list[dict]] = {state: [] for state in STATUS_ORDER}
    for promo in promos:
        state = promotion_service.effective_state(promo, now)
        grouped[state].append(
            {
                "promo": promo,
                "state": state,
                "audience": _audience_summary(promo.targeting),
                "stats": stats.get(promo.id, {}),
                "starts": _to_ist_field(promo.starts_at),
                "ends": _to_ist_field(promo.ends_at),
            }
        )
    return await _render(
        request,
        admin,
        db,
        "promotions.html",
        {
            "grouped": grouped,
            "order": STATUS_ORDER,
            "counts": {k: len(v) for k, v in grouped.items()},
        },
    )


@router.post("/new")
async def create(
    request: Request, admin: RequireEditor, db: DbSession, name: str = Form(default="")
) -> RedirectResponse:
    promo = Promotion(
        id=uuid.uuid4(),
        name=(name or "").strip() or "Untitled campaign",
        kind=KIND_BANNER,
        placement=PLACEMENT_HOME_TOP,
        status=STATUS_DRAFT,
        targeting={},
        frequency={},
        created_by=admin.id,
        updated_by=admin.id,
    )
    db.add(promo)
    await db.commit()
    await security.audit(
        db,
        "promotion.create",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=promo.name,
        ip=client_ip(request),
    )
    return RedirectResponse(f"/promotions/{promo.id}", status_code=303)


@router.get("/entity-search")
async def entity_search(
    request: Request, admin: RequireEditor, db: DbSession, q: str = ""
) -> HTMLResponse:
    """Typeahead behind the destination picker — books, authors or publishers.

    Same shape as the book field, so "send them to an author's page" is a
    search rather than a hand-copied UUID (owner request, 31 Jul 2026). The
    app already routes /book/:workId/:editionId, /catalog/authors/:id and
    /catalog/publishers/:id, so every result maps to a real screen.
    """
    query = q.strip()
    groups: list[dict] = []
    if len(query) >= 2:
        books = []
        for w in await catalog_service.search_local(db, query, limit=5):
            edition = next(iter(w.editions or []), None)
            if edition is None:
                continue  # a Work with no Edition has no book page to open
            books.append(
                {
                    "path": f"/book/{w.id}/{edition.id}",
                    "title": w.title,
                    "sub": ", ".join(a.name for a in w.authors) or "—",
                }
            )
        authors = [
            {"path": f"/catalog/authors/{a.id}", "title": a.name, "sub": "Author page"}
            for a in await catalog_service.search_authors(db, query, limit=4)
        ]
        publishers = [
            {"path": f"/catalog/publishers/{p.id}", "title": p.name, "sub": "Publisher page"}
            for p in await catalog_service.search_publishers(db, query, limit=3)
        ]
        # One box over all three rather than "pick a kind, then search": the
        # operator knows the name, not which table it lives in.
        groups = [
            {"label": "Books", "rows": books},
            {"label": "Authors", "rows": authors},
            {"label": "Publishers", "rows": publishers},
        ]
    return templates.TemplateResponse(
        request, "_promo_dest_results.html", {"groups": groups, "query": query}
    )


async def _set_subject(db: DbSession, promo: Promotion, kind: str, subject_id: str) -> None:
    """Point the campaign at one catalog thing, clearing the others.

    Exactly one subject at a time: a campaign that is "about" both a book and a
    publisher has no single image or title to draw, and the card only has room
    for one anyway.
    """
    promo.work_id = promo.edition_id = promo.author_id = promo.publisher_id = None
    if not subject_id:
        return
    try:
        parsed = uuid.UUID(subject_id)
    except ValueError:
        return

    if kind == "author":
        if await db.get(Author, parsed):
            promo.author_id = parsed
        return
    if kind == "publisher":
        if await db.get(Publisher, parsed):
            promo.publisher_id = parsed
        return

    work = await db.get(Work, parsed)
    if work is None:
        return
    promo.work_id = work.id
    # The card deep-links to a *page*, which needs an edition — take the
    # earliest, the same one the app's own book page settles on.
    edition = (
        (
            await db.execute(
                select(Edition)
                .where(Edition.work_id == work.id, Edition.deleted_at.is_(None))
                .order_by(Edition.created_at.asc())
                .limit(1)
            )
        )
        .scalars()
        .first()
    )
    promo.edition_id = edition.id if edition else None


@router.post("/{promotion_id}/image/remove")
async def remove_campaign_image(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    language: str = Form(default=""),
) -> RedirectResponse:
    """Clear this variant's artwork.

    Immediate, to match upload — the two image controls act at once while the
    text fields wait for Save, and having one of the pair behave differently is
    worse than either rule on its own.

    The stored object is left in the bucket rather than deleted: it may be
    referenced elsewhere (a pasted URL can be reused), the cost is kilobytes,
    and a delete that half-succeeds is a worse failure than an orphan.
    """
    await _get_or_404(db, promotion_id)
    lang = language.strip() or None
    content = (
        (
            await db.execute(
                select(PromotionContent).where(
                    PromotionContent.promotion_id == promotion_id,
                    (
                        PromotionContent.language.is_(None)
                        if lang is None
                        else PromotionContent.language == lang
                    ),
                )
            )
        )
        .scalars()
        .first()
    )
    resp = RedirectResponse(
        f"/promotions/{promotion_id}?tab=content&lang={lang or ''}", status_code=303
    )
    if content is None or not content.image_url:
        set_flash(resp, "err", "There was no image to remove.")
        return resp
    previous, content.image_url = content.image_url, None
    await db.commit()
    await security.audit(
        db,
        "promotion.remove_image",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promotion_id,
        # The URL goes in the trail so a mistaken removal is recoverable by
        # pasting it back — the file itself is still in the bucket.
        summary=f"{lang or 'default'} variant · was {previous}",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Image removed. The file is still in the bucket if you need it back.")
    return resp


@router.post("/{promotion_id}/upload")
async def upload_campaign_image(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    language: str = Form(default=""),
    image: UploadFile | None = None,
) -> RedirectResponse:
    """Upload the campaign's own artwork to R2 and store its URL on the copy.

    Per language variant, because the artwork is part of the copy — a Malayalam
    card may well want different art from the English one.
    """
    await _get_or_404(db, promotion_id)
    lang = language.strip() or None
    resp = RedirectResponse(
        f"/promotions/{promotion_id}?tab=content&lang={lang or ''}", status_code=303
    )
    if image is None or not image.filename:
        set_flash(resp, "err", "No file chosen.")
        return resp
    try:
        url = await assets.upload_image(
            "campaigns", image.filename, await image.read(), image.content_type
        )
    except assets.UploadError as exc:
        set_flash(resp, "err", str(exc))
        return resp

    content = (
        (
            await db.execute(
                select(PromotionContent).where(
                    PromotionContent.promotion_id == promotion_id,
                    (
                        PromotionContent.language.is_(None)
                        if lang is None
                        else PromotionContent.language == lang
                    ),
                )
            )
        )
        .scalars()
        .first()
    )
    if content is None:
        set_flash(resp, "err", "Write the copy first, then add the image.")
        return resp
    content.image_url = url
    await db.commit()
    await security.audit(
        db,
        "promotion.upload_image",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promotion_id,
        summary=f"{lang or 'default'} variant",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Image uploaded.")
    return resp


@router.get("/subject-search")
async def subject_search(
    request: Request, admin: RequireEditor, db: DbSession, q: str = ""
) -> HTMLResponse:
    """Typeahead for the campaign's featured subject — a book, an author or a
    publisher, from one box.

    Reuses the catalog's own search, so it's typo-tolerant and cross-script
    ("keezhalan" finds കീഴാളൻ). The alternative was copying a UUID out of the
    catalog page by hand (owner request, 31 Jul 2026).
    """
    query = q.strip()
    groups: list[dict] = []
    if len(query) >= 2:
        groups = [
            {
                "label": "Books",
                "rows": [
                    {
                        "kind": "book",
                        "id": str(w.id),
                        "title": w.title,
                        "sub": ", ".join(a.name for a in w.authors) or "—",
                        "has_image": any(e.cover_url for e in (w.editions or [])),
                    }
                    for w in await catalog_service.search_local(db, query, limit=5)
                ],
            },
            {
                "label": "Authors",
                "rows": [
                    {
                        "kind": "author",
                        "id": str(a.id),
                        "title": a.name,
                        "sub": a.pen_name or "Author",
                        "has_image": bool(a.image_url),
                    }
                    for a in await catalog_service.search_authors(db, query, limit=4)
                ],
            },
            {
                "label": "Publishers",
                "rows": [
                    {
                        "kind": "publisher",
                        "id": str(p.id),
                        "title": p.name,
                        "sub": "Publisher",
                        "has_image": bool(p.logo_url),
                    }
                    for p in await catalog_service.search_publishers(db, query, limit=3)
                ],
            },
        ]
    return templates.TemplateResponse(
        request, "_promo_subject_results.html", {"groups": groups, "query": query}
    )


# --------------------------------------------------------------------------
# Composer
# --------------------------------------------------------------------------


@router.get("/{promotion_id}")
async def edit(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    tab: str = "content",
    lang: str | None = None,
) -> HTMLResponse:
    promo = await _get_or_404(db, promotion_id)
    contents = await _contents(db, promotion_id)
    now = datetime.now(UTC)

    # Which variant the form is editing. `lang` absent means "pick one for me";
    # `lang=` (empty) explicitly means the default variant. The distinction
    # matters: asking for a language that has no row yet must open an *empty*
    # form, not the default's copy pre-filled — otherwise "add Malayalam"
    # silently duplicates the English into it.
    if lang is None:
        editing_language = (
            None
            if any(c.language is None for c in contents) or not contents
            else contents[0].language
        )
    else:
        editing_language = lang.strip() or None
    selected = next((c for c in contents if c.language == editing_language), None)

    subject = None
    if promo.author_id:
        row = await db.get(Author, promo.author_id)
        if row:
            subject = {
                "kind": "author",
                "id": str(row.id),
                "title": row.name,
                "image": row.image_url,
            }
    elif promo.publisher_id:
        row = await db.get(Publisher, promo.publisher_id)
        if row:
            subject = {
                "kind": "publisher",
                "id": str(row.id),
                "title": row.name,
                "image": row.logo_url,
            }
    elif promo.work_id:
        row = (await db.execute(select(Work).where(Work.id == promo.work_id))).scalars().first()
        if row:
            cover = next((e.cover_url for e in (row.editions or []) if e.cover_url), None)
            subject = {"kind": "book", "id": str(row.id), "title": row.title, "image": cover}

    ctx = {
        "promo": promo,
        "tab": tab if tab in ("content", "audience", "schedule", "results") else "content",
        "contents": contents,
        "selected": selected,
        "editing_language": editing_language,
        "state": promotion_service.effective_state(promo, now),
        "blockers": _blockers(promo, contents),
        "notes": _notes(promo, contents),
        "audience": _audience_summary(promo.targeting),
        "summary": _audience_summary(promo.targeting),
        "targeting": promo.targeting or {},
        "frequency": promo.frequency or {},
        "starts_field": _to_ist_field(promo.starts_at),
        "ends_field": _to_ist_field(promo.ends_at),
        "languages": COMMON_LANGUAGES,
        "kinds": KINDS,
        "card_styles": CARD_STYLES,
        "placements": PLACEMENTS,
        "actions": ACTIONS,
        "subject": subject,
        "uploads_on": assets.configured(),
        "uploads_why": assets.why_not_configured(),
        "estimate": await promotion_service.estimate_audience(db, promo.targeting),
        "stats": (await _stats(db, [promo.id])).get(promo.id, {}),
        "by_language": await _stats_by_language(db, promo.id),
        "audit": await _audit_trail(db, promo.id),
        "banner_placement": PLACEMENT_HOME_TOP,
        "stream_placement": PLACEMENT_HOME_STREAM,
    }
    return await _render(request, admin, db, "promo_edit.html", ctx)


async def _stats_by_language(db: DbSession, promotion_id: uuid.UUID) -> list[dict]:
    """Impressions and clicks per variant — how you find out whether the
    Malayalam copy actually did anything, or the Malayalam audience just
    tolerated the English."""
    rows = (
        await db.execute(
            select(PromotionEvent.language, PromotionEvent.kind, func.count())
            .where(PromotionEvent.promotion_id == promotion_id)
            .group_by(PromotionEvent.language, PromotionEvent.kind)
        )
    ).all()
    buckets: dict[str | None, dict] = {}
    for language, kind, count in rows:
        bucket = buckets.setdefault(language, {"impressions": 0, "clicks": 0})
        if kind == "impression":
            bucket["impressions"] = count
        elif kind == "click":
            bucket["clicks"] = count
    out = []
    for language, bucket in buckets.items():
        seen = bucket["impressions"]
        out.append(
            {
                "language": language or "Default",
                "impressions": seen,
                "clicks": bucket["clicks"],
                "ctr": round(100 * bucket["clicks"] / seen, 1) if seen else None,
            }
        )
    return sorted(out, key=lambda r: -r["impressions"])


async def _audit_trail(db: DbSession, promotion_id: uuid.UUID) -> list:
    from app.models import AdminAuditLog  # noqa: PLC0415

    return list(
        (
            await db.execute(
                select(AdminAuditLog)
                .where(
                    AdminAuditLog.target_type == "promotion",
                    AdminAuditLog.target_id == str(promotion_id),
                )
                .order_by(AdminAuditLog.created_at.desc())
                .limit(20)
            )
        )
        .scalars()
        .all()
    )


@router.post("/{promotion_id}/content")
async def save_content(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    name: str = Form(default=""),
    kind: str = Form(default=KIND_BANNER),
    card_style: str = Form(default=""),
    placement: str = Form(default=PLACEMENT_HOME_TOP),
    sponsor: str = Form(default=""),
    subject_kind: str = Form(default=""),
    subject_id: str = Form(default=""),
    language: str = Form(default=""),
    headline: str = Form(default=""),
    body: str = Form(default=""),
    cta_label: str = Form(default=""),
    image_url: str = Form(default=""),
    action_type: str = Form(default="none"),
    action_value: str = Form(default=""),
) -> RedirectResponse:
    promo = await _get_or_404(db, promotion_id)
    promo.name = name.strip() or promo.name
    promo.kind = kind if kind in KINDS else promo.kind
    promo.card_style = (card_style or None) if promo.kind == KIND_CARD else None
    promo.placement = placement if placement in PLACEMENTS else promo.placement
    promo.sponsor = sponsor.strip() or None
    promo.updated_by = admin.id

    await _set_subject(db, promo, subject_kind.strip(), subject_id.strip())

    lang = language.strip() or None
    if headline.strip():
        existing = (
            (
                await db.execute(
                    select(PromotionContent).where(
                        PromotionContent.promotion_id == promotion_id,
                        (
                            PromotionContent.language.is_(None)
                            if lang is None
                            else PromotionContent.language == lang
                        ),
                    )
                )
            )
            .scalars()
            .first()
        )
        target = existing or PromotionContent(
            id=uuid.uuid4(), promotion_id=promotion_id, language=lang, headline=""
        )
        target.headline = headline.strip()
        target.body = body.strip() or None
        target.cta_label = cta_label.strip() or None
        target.image_url = image_url.strip() or None
        target.action_type = action_type if action_type in ACTIONS else "none"
        target.action_value = action_value.strip() or None
        if existing is None:
            db.add(target)
    await db.commit()
    await security.audit(
        db,
        "promotion.edit_content",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=f"{promo.name} · {lang or 'default'} copy",
        ip=client_ip(request),
    )
    resp = RedirectResponse(
        f"/promotions/{promotion_id}?tab=content&lang={lang or ''}", status_code=303
    )
    set_flash(resp, "ok", "Saved.")
    return resp


@router.post("/{promotion_id}/variants/delete")
async def delete_variant(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    language: str = Form(default=""),
) -> RedirectResponse:
    await _get_or_404(db, promotion_id)
    lang = language.strip() or None
    await db.execute(
        delete(PromotionContent).where(
            PromotionContent.promotion_id == promotion_id,
            (
                PromotionContent.language.is_(None)
                if lang is None
                else PromotionContent.language == lang
            ),
        )
    )
    await db.commit()
    await security.audit(
        db,
        "promotion.delete_variant",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promotion_id,
        summary=lang or "default",
        ip=client_ip(request),
    )
    resp = RedirectResponse(f"/promotions/{promotion_id}?tab=content", status_code=303)
    set_flash(resp, "ok", f"Removed the {lang or 'default'} copy.")
    return resp


@router.post("/{promotion_id}/audience")
async def save_audience(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    languages: Annotated[list[str], Form()] = (),
    platform: Annotated[list[str], Form()] = (),
    app_version_min: str = Form(default=""),
    app_version_max: str = Form(default=""),
    account_age_min: str = Form(default=""),
    account_age_max: str = Form(default=""),
    library_min: str = Form(default=""),
    library_max: str = Form(default=""),
    has_status: Annotated[list[str], Form()] = (),
    genres: str = Form(default=""),
    reader_ids: str = Form(default=""),
    exclude_reader_ids: str = Form(default=""),
    rollout_percent: str = Form(default="100"),
) -> RedirectResponse:
    promo = await _get_or_404(db, promotion_id)
    before = _audience_summary(promo.targeting)
    before_estimate = await promotion_service.estimate_audience(db, promo.targeting)

    targeting: dict = {}
    if languages:
        targeting["languages"] = list(languages)
    if platform:
        targeting["platform"] = list(platform)
    if app_version_min.strip():
        targeting["app_version_min"] = app_version_min.strip()
    if app_version_max.strip():
        targeting["app_version_max"] = app_version_max.strip()
    age = {
        k: v
        for k, v in (("min", _int_or_none(account_age_min)), ("max", _int_or_none(account_age_max)))
        if v is not None
    }
    if age:
        targeting["account_age_days"] = age
    size = {
        k: v
        for k, v in (("min", _int_or_none(library_min)), ("max", _int_or_none(library_max)))
        if v is not None
    }
    if size:
        targeting["library_size"] = size
    if has_status:
        targeting["has_status"] = list(has_status)
    if genre_list := _csv(genres):
        targeting["genres"] = genre_list
    if ids := _csv(reader_ids):
        targeting["reader_ids"] = ids
    if excluded := _csv(exclude_reader_ids):
        targeting["exclude_reader_ids"] = excluded
    rollout = _int_or_none(rollout_percent)
    if rollout is not None and rollout != 100:
        targeting["rollout_percent"] = max(0, min(100, rollout))

    promo.targeting = targeting
    promo.updated_by = admin.id
    await db.commit()

    after_estimate = await promotion_service.estimate_audience(db, targeting)
    await security.audit(
        db,
        "promotion.edit_audience",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=(
            f"{before} → {_audience_summary(targeting)} "
            f"(estimate {before_estimate['matched']} → {after_estimate['matched']})"
        ),
        ip=client_ip(request),
    )
    resp = RedirectResponse(f"/promotions/{promotion_id}?tab=audience", status_code=303)
    set_flash(resp, "ok", f"Audience saved — {after_estimate['matched']} readers match.")
    return resp


@router.post("/{promotion_id}/schedule")
async def save_schedule(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    promotion_id: uuid.UUID,
    starts_at: str = Form(default=""),
    ends_at: str = Form(default=""),
    open_ended: str = Form(default=""),
    priority: str = Form(default="5"),
    max_impressions: str = Form(default=""),
    min_hours_between: str = Form(default="24"),
    redisplay_after_days: str = Form(default=""),
    dismissible: str = Form(default=""),
) -> RedirectResponse:
    promo = await _get_or_404(db, promotion_id)
    promo.starts_at = _to_utc(starts_at)
    parsed_end = _to_utc(ends_at)
    # A typed end date wins over a stale tick. The checkbox used to be checked
    # by default on every new campaign, so typing an end date and pressing Save
    # silently threw it away (owner report, 31 Jul 2026) — the one failure mode
    # a date field must never have.
    promo.open_ended = bool(open_ended) and parsed_end is None
    promo.ends_at = None if promo.open_ended else parsed_end
    promo.priority = _int_or_none(priority) or 5

    frequency: dict = {"dismissible": bool(dismissible)}
    if (cap := _int_or_none(max_impressions)) is not None:
        frequency["max_impressions"] = cap
    gap = _int_or_none(min_hours_between)
    frequency["min_hours_between"] = 24 if gap is None else gap
    if (redisplay := _int_or_none(redisplay_after_days)) is not None:
        frequency["redisplay_after_days"] = redisplay
    promo.frequency = frequency
    promo.updated_by = admin.id
    await db.commit()
    await security.audit(
        db,
        "promotion.edit_schedule",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=(
            f"{_to_ist_field(promo.starts_at)} → "
            f"{_to_ist_field(promo.ends_at) or 'open-ended'} IST"
        ),
        ip=client_ip(request),
    )
    resp = RedirectResponse(f"/promotions/{promotion_id}?tab=schedule", status_code=303)
    set_flash(resp, "ok", "Schedule saved.")
    return resp


# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------


@router.post("/{promotion_id}/publish")
async def publish(
    request: Request, admin: RequireEditor, db: DbSession, promotion_id: uuid.UUID
) -> RedirectResponse:
    promo = await _get_or_404(db, promotion_id)
    contents = await _contents(db, promotion_id)
    blockers = _blockers(promo, contents)
    if blockers:
        resp = RedirectResponse(f"/promotions/{promotion_id}", status_code=303)
        set_flash(resp, "err", f"Not ready: {blockers[0]}")
        return resp

    estimate = await promotion_service.estimate_audience(db, promo.targeting)
    promo.status = STATUS_PUBLISHED
    promo.published_at = promo.published_at or datetime.now(UTC)
    promo.updated_by = admin.id
    await db.commit()
    await security.audit(
        db,
        "promotion.publish",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=(
            f"{promo.name} · audience {estimate['matched']} · "
            f"variants {', '.join(c.language or 'default' for c in contents)}"
        ),
        ip=client_ip(request),
    )
    resp = RedirectResponse(f"/promotions/{promotion_id}?tab=results", status_code=303)
    set_flash(resp, "ok", f"Published to {estimate['matched']} readers.")
    return resp


@router.post("/{promotion_id}/pause")
async def pause(
    request: Request, admin: RequireEditor, db: DbSession, promotion_id: uuid.UUID
) -> RedirectResponse:
    """Stop now — no confirmation dialog on purpose. When a promo is wrong you
    want it gone in one tap, and pausing is reversible."""
    promo = await _get_or_404(db, promotion_id)
    promo.status = STATUS_PAUSED
    promo.updated_by = admin.id
    await db.commit()
    await security.audit(
        db,
        "promotion.pause",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=promo.name,
        ip=client_ip(request),
    )
    resp = RedirectResponse("/promotions", status_code=303)
    set_flash(resp, "ok", f"Stopped “{promo.name}”. Readers stop seeing it on their next fetch.")
    return resp


@router.post("/{promotion_id}/resume")
async def resume(
    request: Request, admin: RequireEditor, db: DbSession, promotion_id: uuid.UUID
) -> RedirectResponse:
    promo = await _get_or_404(db, promotion_id)
    promo.status = STATUS_PUBLISHED
    promo.updated_by = admin.id
    await db.commit()
    await security.audit(
        db,
        "promotion.resume",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=promo.name,
        ip=client_ip(request),
    )
    resp = RedirectResponse("/promotions", status_code=303)
    set_flash(resp, "ok", f"“{promo.name}” is live again.")
    return resp


@router.post("/{promotion_id}/duplicate")
async def duplicate(
    request: Request, admin: RequireEditor, db: DbSession, promotion_id: uuid.UUID
) -> RedirectResponse:
    source = await _get_or_404(db, promotion_id)
    copy = Promotion(
        id=uuid.uuid4(),
        name=f"{source.name} (copy)",
        kind=source.kind,
        card_style=source.card_style,
        placement=source.placement,
        status=STATUS_DRAFT,
        sponsor=source.sponsor,
        priority=source.priority,
        # Dates deliberately not copied: a duplicated campaign that inherits
        # last month's window would publish straight into "ended".
        targeting=dict(source.targeting or {}),
        frequency=dict(source.frequency or {}),
        work_id=source.work_id,
        edition_id=source.edition_id,
        author_id=source.author_id,
        publisher_id=source.publisher_id,
        created_by=admin.id,
        updated_by=admin.id,
    )
    db.add(copy)
    for content in await _contents(db, promotion_id):
        db.add(
            PromotionContent(
                id=uuid.uuid4(),
                promotion_id=copy.id,
                language=content.language,
                headline=content.headline,
                body=content.body,
                cta_label=content.cta_label,
                image_url=content.image_url,
                action_type=content.action_type,
                action_value=content.action_value,
            )
        )
    await db.commit()
    await security.audit(
        db,
        "promotion.duplicate",
        admin_id=admin.id,
        target_type="promotion",
        target_id=copy.id,
        summary=f"from {source.name}",
        ip=client_ip(request),
    )
    return RedirectResponse(f"/promotions/{copy.id}", status_code=303)


@router.post("/{promotion_id}/delete")
async def soft_delete(
    request: Request, admin: RequireEditor, db: DbSession, promotion_id: uuid.UUID
) -> RedirectResponse:
    promo = await _get_or_404(db, promotion_id)
    # Soft delete only (rule 3) — events reference this row forever, and a
    # deleted campaign's numbers are still the record of what readers saw.
    promo.deleted_at = datetime.now(UTC)
    promo.status = STATUS_PAUSED
    promo.updated_by = admin.id
    await db.commit()
    await security.audit(
        db,
        "promotion.delete",
        admin_id=admin.id,
        target_type="promotion",
        target_id=promo.id,
        summary=promo.name,
        ip=client_ip(request),
    )
    resp = RedirectResponse("/promotions", status_code=303)
    set_flash(resp, "ok", f"Deleted “{promo.name}”.")
    return resp


# --------------------------------------------------------------------------
# Live audience estimate (fragment)
# --------------------------------------------------------------------------


@router.post("/estimate")
async def estimate(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    languages: Annotated[list[str], Form()] = (),
    platform: Annotated[list[str], Form()] = (),
    account_age_min: str = Form(default=""),
    account_age_max: str = Form(default=""),
    library_min: str = Form(default=""),
    library_max: str = Form(default=""),
    has_status: Annotated[list[str], Form()] = (),
    genres: str = Form(default=""),
    reader_ids: str = Form(default=""),
    exclude_reader_ids: str = Form(default=""),
    rollout_percent: str = Form(default="100"),
) -> HTMLResponse:
    """Re-run the real serve predicate against the form as it stands.

    Reuses `promotion_service.matches` rather than a second implementation:
    the whole point of the estimate is that it agrees with what will actually
    be served, and two copies of the same rules drift the first time one is
    edited.
    """
    targeting: dict = {}
    if languages:
        targeting["languages"] = list(languages)
    if platform:
        targeting["platform"] = list(platform)
    age = {
        k: v
        for k, v in (("min", _int_or_none(account_age_min)), ("max", _int_or_none(account_age_max)))
        if v is not None
    }
    if age:
        targeting["account_age_days"] = age
    size = {
        k: v
        for k, v in (("min", _int_or_none(library_min)), ("max", _int_or_none(library_max)))
        if v is not None
    }
    if size:
        targeting["library_size"] = size
    if has_status:
        targeting["has_status"] = list(has_status)
    if genre_list := _csv(genres):
        targeting["genres"] = genre_list
    if ids := _csv(reader_ids):
        targeting["reader_ids"] = ids
    if excluded := _csv(exclude_reader_ids):
        targeting["exclude_reader_ids"] = excluded
    rollout = _int_or_none(rollout_percent)
    if rollout is not None and rollout != 100:
        targeting["rollout_percent"] = max(0, min(100, rollout))

    # Step-by-step narrowing: the rule that drops the most is usually the one
    # you didn't mean to add.
    steps = [
        {
            "label": "Everyone",
            "count": (await promotion_service.estimate_audience(db, {}))["matched"],
        }
    ]
    partial: dict = {}
    for key in (
        "languages",
        "platform",
        "account_age_days",
        "library_size",
        "has_status",
        "genres",
        "reader_ids",
        "exclude_reader_ids",
    ):
        if key in targeting:
            partial[key] = targeting[key]
            steps.append(
                {
                    "label": "+ "
                    + _audience_summary({key: targeting[key]}).replace("Everyone · ", ""),
                    "count": (await promotion_service.estimate_audience(db, dict(partial)))[
                        "matched"
                    ],
                }
            )

    result = await promotion_service.estimate_audience(db, targeting)
    return templates.TemplateResponse(
        request,
        "_promo_estimate.html",
        {"estimate": result, "steps": steps, "summary": _audience_summary(targeting)},
    )
