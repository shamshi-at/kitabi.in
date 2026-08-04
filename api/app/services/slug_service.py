"""Stable, human-readable URL slugs for the public catalog pages.

`/book/chemmeen` instead of `/b/47e95a54-829f-5f0c-bdea-f4f3be8c6bbe`. A UUID in
a URL looks like spam in a search result, carries no keyword relevance, and
can't be said out loud — and the entire point of the public web platform is to
be found (docs/web-platform-plan.md §4.1).

Two properties matter, and they pull in opposite directions:

**Stable.** A slug is a published URL. Regenerating it when a title is edited
would break every inbound link and throw away whatever ranking the page had, so
slugs are written **once, on insert, and never recomputed** — deliberately
unlike the `*_translit` search columns next door, which are refreshed on every
write by `models/translit_hooks.py`. A retitled book keeps its old slug; that is
correct, and it is what every CMS worth using does.

**Unique.** Enforced by a unique index, not by hope. Uniqueness needs a database
round trip, which an ORM `before_insert` hook cannot do (it isn't async), so
slugs are assigned by `ensure_slug` at the service layer.

Because "assign at the service layer" means "every write path has to remember",
`backfill_missing` exists as the safety net: an idempotent pass that fills any
`slug IS NULL` row. It runs on a schedule, so a row created by a path nobody
updated (an ETL bulk load, a future importer) still gets a slug without anyone
noticing the gap. The column stays nullable for the same reason — a missing slug
must degrade to "reachable by UUID", never to a failed insert.
"""

from __future__ import annotations

import re
from typing import Any

from sqlalchemy import func, select
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Author, Publisher, Series, Work
from app.services.translit import transliterate

# Slugs are capped well under Postgres' index limits and under what a search
# result will display; a 300-character slug helps nobody.
MAX_SLUG_LEN = 80

_NON_WORD = re.compile(r"[^a-z0-9]+")
_TRIM = re.compile(r"^-+|-+$")

# Slugs that would collide with a real route on the public site. A book
# genuinely titled "Search" must not claim /book/search's sibling namespace by
# accident — it gets "search-2" instead.
RESERVED = frozenset(
    {
        "search",
        "browse",
        "book",
        "books",
        "author",
        "authors",
        "publisher",
        "publishers",
        "genre",
        "genres",
        "language",
        "languages",
        "series",
        "list",
        "lists",
        "reader",
        "readers",
        "translations",
        "sitemaps",
        "robots",
        "privacy",
        "terms",
        "api",
        "img",
        "assets",
        "static",
        "b",
        "a",
        "p",
    }
)


def slugify(text: str | None) -> str | None:
    """`"ചെമ്മീൻ"` → `"chemmeen"`, `"The Guide"` → `"the-guide"`.

    Routed through `transliterate` so a Malayalam or Tamil title produces a
    typeable Latin slug rather than percent-encoded mojibake — the same
    capability that already lets an English keyboard search the catalog, reused
    for URLs. Returns None when nothing survives (a title of only punctuation),
    and the caller falls back to the UUID.
    """
    romanized = transliterate(text)
    if romanized is None:
        return None
    value = _NON_WORD.sub("-", romanized.lower())
    value = _TRIM.sub("", value)[:MAX_SLUG_LEN]
    value = _TRIM.sub("", value)  # a truncation may have left a trailing dash
    return value or None


def _candidates(base: str, extras: list[str]) -> list[str]:
    """`base`, then progressively more qualified forms — "chemmeen",
    "chemmeen-thakazhi", "chemmeen-thakazhi-1956". A disambiguated slug should
    read like a fact about the book, so try meaningful qualifiers before
    falling back to a meaningless counter."""
    out = [base]
    acc = base
    for extra in extras:
        piece = slugify(extra)
        if not piece:
            continue
        acc = f"{acc}-{piece}"[:MAX_SLUG_LEN]
        acc = _TRIM.sub("", acc)
        if acc and acc not in out:
            out.append(acc)
    return out


async def _taken(db: AsyncSession, model: type, slug: str, exclude_id: Any = None) -> bool:
    stmt = select(func.count()).select_from(model).where(model.slug == slug)
    if exclude_id is not None:
        stmt = stmt.where(model.id != exclude_id)
    return bool(await db.scalar(stmt))


async def unique_slug(
    db: AsyncSession,
    model: type,
    text: str | None,
    *,
    extras: list[str] | None = None,
    exclude_id: Any = None,
) -> str | None:
    """The first free slug for `text`, qualified by `extras` when the plain form
    is taken, then suffixed `-2`, `-3`… as a last resort. None when `text`
    romanizes to nothing."""
    base = slugify(text)
    if base is None:
        return None
    if base in RESERVED:
        base = f"{base}-2"

    for candidate in _candidates(base, extras or []):
        if candidate not in RESERVED and not await _taken(db, model, candidate, exclude_id):
            return candidate

    # Everything meaningful is taken. Counter suffix, bounded so a pathological
    # catalog can't spin here — past the bound the caller keeps a null slug and
    # the page stays reachable by UUID.
    stem = _candidates(base, extras or [])[-1]
    for n in range(2, 100):
        candidate = f"{stem[: MAX_SLUG_LEN - 4]}-{n}"
        if not await _taken(db, model, candidate, exclude_id):
            return candidate
    return None


def work_extras(work: Work, authors: list[Author] | None = None) -> list[str]:
    """Disambiguators for a Work's slug, best first: author, then year.

    When `authors` isn't supplied this reads `work.authors` **only if that
    relationship is already loaded**. Touching an unloaded relationship here
    emits a lazy load in sync context and raises MissingGreenlet — and this runs
    on write paths (creation, backfill) where it frequently isn't loaded. The
    explicit `unloaded` check means callers get author disambiguation for free
    when the data is in hand, and silently fall back to the year when it isn't,
    with no implicit IO either way.
    """
    if authors is None and "authors" not in sa_inspect(work).unloaded:
        authors = list(work.authors)
    extras: list[str] = []
    if authors:
        extras.append(authors[0].pen_name or authors[0].name)
    if work.first_publish_year:
        extras.append(str(work.first_publish_year))
    return extras


async def ensure_slug(
    db: AsyncSession,
    obj: Work | Author | Publisher | Series,
    *,
    extras: list[str] | None = None,
) -> str | None:
    """Assign a slug if this row has none. **Never overwrites an existing one** —
    that is the stability guarantee, and it's why this is safe to call from any
    write path, including updates.

    `extras` are the disambiguators tried before a bare counter; see
    `work_extras`. Never read from a relationship here (see above).
    """
    if getattr(obj, "slug", None):
        return obj.slug

    if isinstance(obj, Work):
        text = obj.title
        extras = extras if extras is not None else work_extras(obj)
    elif isinstance(obj, Author):
        text = obj.pen_name or obj.name
    else:
        text = obj.name

    obj.slug = await unique_slug(db, type(obj), text, extras=extras or [], exclude_id=obj.id)
    return obj.slug


_BACKFILL_MODELS: tuple[type, ...] = (Work, Author, Publisher, Series)


async def backfill_missing(db: AsyncSession, *, limit: int = 500) -> int:
    """Fill `slug IS NULL` rows, newest first. Idempotent and interruptible —
    it exists so a write path that forgot `ensure_slug` (an ETL bulk load, a
    future importer) self-heals instead of silently publishing UUID URLs.

    Returns how many were filled. Bounded per call so a scheduled run can never
    become a long transaction against production.
    """
    filled = 0
    for model in _BACKFILL_MODELS:
        remaining = limit - filled
        if remaining <= 0:
            break
        stmt = (
            select(model)
            .where(model.slug.is_(None), model.deleted_at.is_(None))
            .order_by(model.created_at.desc())
            .limit(remaining)
        )
        # Eager-load authors so `work_extras` can disambiguate by author without
        # a lazy load (which would raise MissingGreenlet from this context).
        if model is Work:
            stmt = stmt.options(selectinload(Work.authors))
        rows = (await db.execute(stmt)).scalars().all()
        for row in rows:
            extras = work_extras(row, list(row.authors)) if model is Work else None
            if await ensure_slug(db, row, extras=extras) is not None:
                filled += 1
    if filled:
        await db.commit()
    return filled
