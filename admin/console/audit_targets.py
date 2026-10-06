"""What an audit line is *about*, as a name and a page to open.

The log's Target column used to read `edition · 1b46d371-c3f` — a type and the
front of an id. Of the kinds of record the console writes lines about, the
catalogue ones were linked and the rest (an edition, an edit, a review) were
plain text, so the question the log exists to answer — "what did they change?" —
needed a database client (owner request, 6 Oct 2026: *"target should be
clickable, so I can see what record it is — for all the audit log types"*).

Each row now resolves to a **name** (the book's title and ISBN, the author, the
reader, the promotion…) and the **page that opens it**. Several kinds have no page
of their own and open their parent: an edition and an edit open the *book* they
belong to; a review opens the book or series it is a review of. A record that has
been deleted, or is gone altogether, is shown by name (or id) and marked, **not
linked**: a deleted book's page just bounces to the catalogue, and a link that
lands somewhere else is worse than none. A target that is not a record at all (a
failed sign-in's `email`) keeps the plain text. A row never disappears from the
log because its subject did.

One query per kind per page, not per row: a page is a hundred lines.
"""

import uuid
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models_ref import (
    AdminUser,
    Author,
    Edition,
    Profile,
    Promotion,
    Publisher,
    Review,
    Series,
    Work,
    WorkRevision,
)

#: The catalogue's own audit lines use the plural ("works", from a merge's `kind`);
#: the rest, the singular. One name for each.
SINGULAR = {"works": "work", "authors": "author", "publishers": "publisher"}

#: Every target type the console can write, and where it opens. The guard test
#: (`test_audit_targets.py`) reads the console's source for `target_type=` and
#: fails if a new one is not decided here — "all the audit log types" has to stay
#: true after the next feature adds one.
OPENS = {
    "work": "the book",
    "author": "the author",
    "publisher": "the publisher",
    "series": "the series",
    "reader": "the reader",
    "promotion": "the campaign",
    "admin": "that admin's entries in this log",
    "edition": "the book the edition belongs to",
    "revision": "the book the edit is for",
    "review": "the book or series reviewed",
}
#: Written as a target but not a record anywhere: a failed sign-in's email address.
NOT_A_RECORD = frozenset({"email"})

MAX_LABEL = 70


@dataclass(frozen=True)
class Target:
    """A resolved target: `kind` and `id` are what `_links.html`'s `target` macro
    opens (a work, an author, a reader…); `label` is what the link says; `linked`
    is False when there is nothing to open (the record is deleted or gone)."""

    kind: str
    id: str
    label: str
    linked: bool = True


class Lookup(Protocol):
    """What resolving needs from the database — a seam, so the rules above are
    tested without one. Returns `{id: row}` for the ids that exist."""

    async def names(self, kind: str, ids: set[str]) -> dict[str, tuple]: ...


def kind_of(target_type: str | None) -> str | None:
    t = (target_type or "").strip().lower()
    return SINGULAR.get(t, t) or None


def _uuid(value: str | None) -> str | None:
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, AttributeError, TypeError):
        return None


def _clip(text: str) -> str:
    return text if len(text) <= MAX_LABEL else text[: MAX_LABEL - 1] + "…"


def _person(row: tuple) -> str:
    full_name, username, email = row
    return full_name or (f"@{username}" if username else email)


async def resolve(rows: Iterable, lookup: Lookup) -> dict:
    """`{audit row id: Target}` for every row whose target is a record — linked if
    it can be opened, marked if it can not. Rows with no id, or a target that is
    not a record (`email`), are left out and keep the old text."""
    rows = list(rows)
    wanted: dict[str, set[str]] = {}
    for row in rows:
        kind, ident = kind_of(row.target_type), _uuid(row.target_id)
        if kind in OPENS and ident:
            wanted.setdefault(kind, set()).add(ident)

    found = {kind: await lookup.names(kind, ids) for kind, ids in wanted.items()}

    out: dict = {}
    for row in rows:
        kind, ident = kind_of(row.target_type), _uuid(row.target_id)
        if kind not in OPENS or not ident:
            continue
        got = found.get(kind, {}).get(ident)
        target = _target(kind, ident, got) if got is not None else None
        out[row.id] = target or Target(kind, ident, f"{ident[:12]} · record gone", linked=False)
    return out


def _named(label: str, ident: str, kind: str, *, deleted: bool) -> Target:
    """A book, linked — or, if it has been soft-deleted, named, marked and not
    linked (its page redirects to the catalogue)."""
    if deleted:
        return Target(kind, ident, _clip(f"{label} · deleted"), linked=False)
    return Target(kind, ident, _clip(label))


def _target(kind: str, ident: str, got: tuple) -> Target | None:
    if kind == "work":
        title, deleted = got
        return _named(title or "(untitled)", ident, "work", deleted=deleted)
    if kind in ("author", "publisher", "series"):
        # A merged-away row still opens: its page says where it went.
        return Target(kind, ident, _clip(got[0] or "(unnamed)"))
    if kind == "reader":
        return Target("reader", ident, _clip(_person(got)))
    if kind == "promotion":
        return Target("promotion", ident, _clip(got[0]))
    if kind == "admin":
        return Target("admin", ident, got[0])
    if kind == "edition":
        title, isbn, work_id, work_deleted = got
        label = f"{title} · {isbn or 'no ISBN'}"
        return _named(label, str(work_id), "work", deleted=work_deleted)
    if kind == "revision":
        title, work_id, work_deleted = got
        return _named(f"Edit of {title}", str(work_id), "work", deleted=work_deleted)
    if kind == "review":
        subject_kind, subject_id, name, deleted = got
        if subject_id is None:
            return None  # a review on nothing: "record gone"
        return _named(f"Review of {name}", str(subject_id), subject_kind, deleted=deleted)
    return None


class DbLookup:
    """The real thing: one `IN (…)` query per kind. Soft-deleted rows are read
    too — a `work.delete` line must still say which book it deleted."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def names(self, kind: str, ids: set[str]) -> dict[str, tuple]:
        keys = [uuid.UUID(i) for i in ids]
        if kind == "review":
            return await self._reviews(keys)
        stmt = self._statement(kind, keys)
        if stmt is None:
            return {}
        return {str(row[0]): tuple(row[1:]) for row in (await self.db.execute(stmt)).all()}

    @staticmethod
    def _statement(kind: str, keys: list[uuid.UUID]):  # noqa: ANN205, PLR0911
        if kind == "work":
            return select(Work.id, Work.title, Work.deleted_at.is_not(None)).where(
                Work.id.in_(keys)
            )
        if kind == "author":
            return select(Author.id, Author.name).where(Author.id.in_(keys))
        if kind == "publisher":
            return select(Publisher.id, Publisher.name).where(Publisher.id.in_(keys))
        if kind == "series":
            return select(Series.id, Series.name).where(Series.id.in_(keys))
        if kind == "reader":
            return select(Profile.id, Profile.full_name, Profile.username, Profile.email).where(
                Profile.id.in_(keys)
            )
        if kind == "promotion":
            return select(Promotion.id, Promotion.name).where(Promotion.id.in_(keys))
        if kind == "admin":
            return select(AdminUser.id, AdminUser.email).where(AdminUser.id.in_(keys))
        if kind == "edition":
            return (
                select(
                    Edition.id,
                    Work.title,
                    Edition.isbn,
                    Edition.work_id,
                    Work.deleted_at.is_not(None),
                )
                .join(Work, Work.id == Edition.work_id)
                .where(Edition.id.in_(keys))
            )
        if kind == "revision":
            return (
                select(
                    WorkRevision.id, Work.title, WorkRevision.work_id, Work.deleted_at.is_not(None)
                )
                .join(Work, Work.id == WorkRevision.work_id)
                .where(WorkRevision.id.in_(keys))
            )
        return None

    async def _reviews(self, keys: list[uuid.UUID]) -> dict[str, tuple]:
        """A review is on a book or on a whole series:
        `(kind, subject id, name, deleted)`."""
        db = self.db
        reviews = (
            await db.execute(
                select(Review.id, Review.work_id, Review.series_id).where(Review.id.in_(keys))
            )
        ).all()
        work_ids = {w for _, w, _ in reviews if w}
        series_ids = {s for _, _, s in reviews if s}
        works: dict = {}
        if work_ids:
            works = {
                wid: (title, bool(deleted))
                for wid, title, deleted in (
                    await db.execute(
                        select(Work.id, Work.title, Work.deleted_at.is_not(None)).where(
                            Work.id.in_(work_ids)
                        )
                    )
                ).all()
            }
        names: dict = {}
        if series_ids:
            names = dict(
                (
                    await db.execute(
                        select(Series.id, Series.name).where(Series.id.in_(series_ids))
                    )
                ).all()
            )
        out: dict[str, tuple] = {}
        for rid, work_id, series_id in reviews:
            if work_id:
                title, deleted = works.get(work_id, ("(untitled)", True))
                out[str(rid)] = ("work", work_id, title or "(untitled)", deleted)
            elif series_id:
                out[str(rid)] = ("series", series_id, names.get(series_id) or "(untitled)", False)
            else:
                out[str(rid)] = ("work", None, "", False)
        return out
