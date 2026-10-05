"""The drill-down page — every number in the console, opened as its rows.

`/activity/<kind>` lists one kind (see `console/activity.py`) under one scope:
a window (`range=24h|today|7|28|90|all`, or an explicit `from`/`to` — what a
column of the growth chart sends), optionally pinned to one reader
(`reader=<id>`) or one book (`work=<id>`). Every choice is in the query string,
so a list is a link somebody can paste to a colleague. The page scrolls: the
same URL fetched with `X-Requested-With: fetch` returns just the next rows.

**Private kinds are audited.** Until 4 Oct 2026 the console had no screen that
showed a reader's shelf, progress, notes or lending at all ("support does not
require voyeurism" — docs/admin_mockups.html). The owner reversed that: an
operator may now open a reader's whole account, and in exchange every opening
is a line in the append-only audit log, with the admin, what they opened and
whose. The audit is written here, on the page load, so no template change can
show private rows without it — and only on the page load, not on each scrolled
page, so one look is one line rather than twenty.
"""

import uuid
from datetime import UTC, datetime
from typing import Annotated
from urllib.parse import urlencode

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .. import activity, insights, queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..models_ref import Profile, Work
from ..templating import templates, to_ist

router = APIRouter(prefix="/activity")

# The windows a list can be narrowed to, in picker order. The dashboard's trend
# ranges plus "today" (the live tiles count from UTC midnight) and "all".
WINDOWS = {
    "24h": "Last 24 hours",
    "today": "Today",
    "7": "Last 7 days",
    "28": "Last 28 days",
    "90": "Last 90 days",
    "all": "All time",
}


def _parse_instant(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        at = datetime.fromisoformat(value.strip().replace(" ", "+"))
    except ValueError:
        return None
    return at if at.tzinfo else at.replace(tzinfo=UTC)


def _display_name(p: Profile | None) -> str:
    if p is None:
        return "a deleted account"
    return p.full_name or (f"@{p.username}" if p.username else p.email)


def _span_label(start: datetime, end: datetime | None) -> str:
    """What an explicit window reads as — in IST, the same clock the rows use.
    The window itself is still the UTC bucket the chart column summed (so the
    rows add up to the number clicked); only its description moves, which is why
    an hour is 13:30–14:30 and a day runs 05:30 to 05:30."""
    first = to_ist(start)
    if end is None:
        return f"Since {first:%-d %b %Y, %H:%M} IST"
    last = to_ist(end)
    if (end - start).total_seconds() <= 3600:
        return f"{first:%-d %b %Y, %H:%M}–{last:%H:%M} IST"
    return f"{first:%-d %b %Y, %H:%M} – {last:%-d %b %Y, %H:%M} IST"


def page_url(request: Request, page: int) -> str:
    """This page's own URL with `page` swapped — relative, so a fetch behind
    Railway's proxy never comes back as an http:// URL on an https:// page."""
    params = [(k, v) for k, v in request.query_params.multi_items() if k != "page"]
    params.append(("page", str(page)))
    return f"{request.url.path}?{urlencode(params)}"


@router.get("")
async def activity_home() -> RedirectResponse:
    return RedirectResponse("/activity/readers?range=today", status_code=303)


@router.get("/{kind}")
async def activity_list(  # noqa: C901, PLR0912, PLR0913
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    kind: str,
    range_: str = Query(default="", alias="range"),
    from_: str | None = Query(default=None, alias="from"),
    to: str | None = Query(default=None),
    reader: Annotated[uuid.UUID | None, Query()] = None,
    work: Annotated[uuid.UUID | None, Query()] = None,
    page: int = Query(default=1, ge=1),
) -> HTMLResponse:
    # --- scope -------------------------------------------------------------
    start = _parse_instant(from_)
    end = _parse_instant(to)
    if start is not None:
        range_ = ""
        window_label = _span_label(start, end)
    else:
        end = None
        if range_ not in WINDOWS:
            # A reader's or a book's list is about the whole of it; the
            # site-wide feed is about today.
            range_ = "all" if (reader or work) else "today"
        start = insights.window_start(range_)
        window_label = WINDOWS[range_]

    scope = activity.Scope(start=start, end=end, reader_id=reader, work_id=work)
    context = scope.context

    subject_reader = await db.get(Profile, reader) if reader else None
    subject_work = await db.get(Work, work) if work else None
    if (reader and subject_reader is None) or (work and subject_work is None):
        return RedirectResponse("/activity/readers?range=today", status_code=303)

    kinds = activity.kinds_for(context)
    if kind not in activity.BY_KEY or activity.BY_KEY[kind] not in kinds:
        params = [(k, v) for k, v in request.query_params.multi_items() if k != "page"]
        return RedirectResponse(f"/activity/{kinds[0].key}?{urlencode(params)}", status_code=303)
    this = activity.BY_KEY[kind]

    rows, more = await activity.rows(db, kind, scope, page)
    next_url = page_url(request, page + 1) if more else None

    # --- the next page of a scrolling list: rows only, no audit line --------
    if request.headers.get("x-requested-with") == "fetch":
        return templates.TemplateResponse(
            request,
            "_activity_rows.html",
            {"admin": admin, "kind": kind, "context": context, "rows": rows, "next_url": next_url},
        )

    tab_counts = await activity.counts(db, scope)
    minutes = await activity.minutes(db, scope) if kind == "sittings" else None

    if this.private:
        whose = (
            f"{_display_name(subject_reader)} ({subject_reader.email})"
            if subject_reader
            else (f"“{subject_work.title}”" if subject_work else "all readers")
        )
        await security.audit(
            db,
            "privacy.view",
            admin_id=admin.id,
            target_type="reader" if reader else ("work" if work else None),
            target_id=str(reader or work) if (reader or work) else None,
            summary=f"{this.label} · {whose} · {window_label if this.windowed else 'right now'}",
            ip=client_ip(request),
        )

    # The links that keep the scope while changing one thing.
    fixed = []
    if reader:
        fixed.append(("reader", str(reader)))
    if work:
        fixed.append(("work", str(work)))
    window_q = [("from", from_), ("to", to)] if from_ else [("range", range_)]
    window_q = [(k, v) for k, v in window_q if v]

    def link(k: str, window: list | None = None) -> str:
        return f"/activity/{k}?{urlencode(fixed + (window_q if window is None else window))}"

    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "activity.html",
        {
            "admin": admin,
            "active": "readers" if reader else ("catalog" if work else "dashboard"),
            "badges": badges,
            "kind": kind,
            "this": this,
            "kinds": kinds,
            "tab_counts": tab_counts,
            "tab_links": {k.key: link(k.key) for k in kinds},
            "windows": WINDOWS,
            "window_links": {key: link(kind, [("range", key)]) for key in WINDOWS},
            "range_key": range_,
            "window_label": window_label,
            "explicit_window": bool(from_),
            "context": context,
            "subject_reader": subject_reader,
            "subject_reader_name": _display_name(subject_reader) if subject_reader else None,
            "subject_work": subject_work,
            "rows": rows,
            "next_url": next_url,
            "minutes": minutes,
            "page": page,
            "flash": None,
        },
    )
