"""Your circle router: what a reader's accepted connections who chose to share
have read, rated and own — for search rows, the book page and Home's one card —
plus asking one of them to lend a copy. Every rule is in services/circle_service.py."""

import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, status
from pydantic import BaseModel

from app.api.catalog import work_summary
from app.api.deps import CurrentUser, DbSession
from app.models.edition import Edition
from app.models.profile import Profile
from app.schemas.circle import (
    CirclePickOut,
    CirclePickResponse,
    CircleSignalsIn,
    CircleSignalsOut,
    CircleWorkOut,
)
from app.services import catalog_service, circle_service, push_service

router = APIRouter(prefix="/circle", tags=["circle"])


async def _caller(db: DbSession, user: dict) -> Profile:
    profile = await db.get(Profile, uuid.UUID(user["id"]))
    if profile is None or profile.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "profile_not_found", "message": "Profile not found"},
        )
    return profile


@router.post("/signals", response_model=CircleSignalsOut)
async def circle_signals(
    payload: CircleSignalsIn, user: CurrentUser, db: DbSession
) -> CircleSignalsOut:
    """One line per search row, for a whole page of results in one request."""
    me = await _caller(db, user)
    people = await circle_service.sharers(db, me.id)
    if not circle_service.shares_anything(me):
        return CircleSignalsOut(invite=len(people))
    return CircleSignalsOut(signals=await circle_service.signals(db, people, payload.work_ids))


@router.get("/works/{work_id}", response_model=CircleWorkOut)
async def circle_work(work_id: uuid.UUID, user: CurrentUser, db: DbSession) -> CircleWorkOut:
    """The book page's circle card and its "See all" sheet."""
    me = await _caller(db, user)
    people = await circle_service.sharers(db, me.id)
    if not circle_service.shares_anything(me):
        return CircleWorkOut(invite=len(people))
    return await circle_service.for_work(db, people, work_id)


@router.get("/pick", response_model=CirclePickResponse)
async def circle_pick(
    user: CurrentUser,
    db: DbSession,
    dismissed: str | None = Query(default=None, max_length=8000),
) -> CirclePickResponse:
    """Home's one "From your circle" card — or none. Stable for the day."""
    me = await _caller(db, user)
    people = await circle_service.sharers(db, me.id)
    if not circle_service.shares_anything(me):
        return CirclePickResponse(invite=len(people))
    chosen = await circle_service.pick(db, me.id, people, circle_service.parse_dismissed(dismissed))
    if chosen is None:
        return CirclePickResponse()
    work = await catalog_service.work_summary_row(db, chosen.work_id)
    if work is None:
        return CirclePickResponse()
    return CirclePickResponse(
        pick=CirclePickOut(
            kind=chosen.kind,
            work=work_summary(work),
            person=chosen.person,
            people=chosen.people,
            also_read_count=chosen.also_read_count,
            my_rating=chosen.my_rating,
        )
    )


class BorrowAskIn(BaseModel):
    owner_id: uuid.UUID
    edition_id: uuid.UUID


# One ask per (asker, owner, edition) a day — a borrow request is a favour, and
# a button that can be tapped twice must not buzz a friend's phone twice.
# SCALE: in-process, so it resets on deploy and divides by instance count; a
# duplicate ask after a restart is a nuisance, not a leak, so Postgres can wait.
_ASKED: dict[tuple[uuid.UUID, uuid.UUID, uuid.UUID], datetime] = {}
_ASK_WINDOW = timedelta(hours=24)


@router.post("/borrow-ask", status_code=status.HTTP_204_NO_CONTENT)
async def borrow_ask(
    payload: BorrowAskIn,
    user: CurrentUser,
    db: DbSession,
    background_tasks: BackgroundTasks,
) -> None:
    """Ask a connection who shares owning a book to lend it. Only answers yes
    for a copy the caller could already see on that book — the same gate as
    the circle card, so this can't be used to probe someone's shelf."""
    me = await _caller(db, user)
    if not circle_service.shares_anything(me):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "not_sharing", "message": "Share your reading to ask your circle."},
        )
    edition = await db.get(Edition, payload.edition_id)
    people = await circle_service.sharers(db, me.id)
    owner = people.get(payload.owner_id)
    visible = None
    if edition is not None and owner is not None:
        persons = (await circle_service.for_work(db, {owner.id: owner}, edition.work_id)).people
        visible = next((p for p in persons if p.owns), None)
    if visible is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "That copy isn't on their shared shelf."},
        )
    now = datetime.now(UTC)
    key = (me.id, owner.id, payload.edition_id)
    last = _ASKED.get(key)
    if last is not None and now - last < _ASK_WINDOW:
        return
    _ASKED[key] = now
    if len(_ASKED) > 5000:
        for k in [k for k, t in _ASKED.items() if now - t >= _ASK_WINDOW]:
            _ASKED.pop(k, None)
    background_tasks.add_task(
        push_service.notify_borrow_ask,
        me.id,
        owner.id,
        edition.work.title,
        edition.work_id,
        visible.owned_edition_id or edition.id,
        edition.cover_url,
    )
