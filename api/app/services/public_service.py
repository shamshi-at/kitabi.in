"""Queries behind the public web site's page-shaped endpoints.

A thin projection over `catalog_service` / `review_service` — this module owns
*assembly* (what belongs on a page, and the content floor that decides whether
it may be indexed), never business logic. If something here starts making
decisions about the catalog rather than about a page, it belongs one layer down.
"""

from __future__ import annotations

import uuid

from sqlalchemy import Select, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import (
    Author,
    Edition,
    Genre,
    LibraryEntry,
    Profile,
    Publisher,
    Rating,
    Review,
    Series,
    Work,
)
from app.models.work import work_authors, work_genres
from app.schemas import public as P
from app.services import (
    catalog_service,
    review_service,
    scoring_service,
    search_rank,
    slug_service,
)
from app.services.translit import fold as fold_of
from app.services.translit import transliterate as translit_of

# --------------------------------------------------------------------------
# The content floor (docs/web-platform-plan.md §8.3)
# --------------------------------------------------------------------------
#
# The counter-intuitive rule: do NOT publish every row. A large share of the
# seeded catalog has an OpenLibrary transliteration-garbage title, no cover, no
# description and one edition. A thousand pages like that teach a search engine
# that this domain produces thin pages, and drag down the two hundred good ones
# — the mechanism that has killed more catalog sites than slow servers.
#
# So a page is indexable only once it carries something a reader would actually
# have come for. It flips on by itself the moment someone adds a cover or a
# blurb, which quietly turns the app's "Improve this entry" flow into the site's
# SEO engine.
MIN_DESCRIPTION_CHARS = 120


def work_is_indexable(
    work: Work,
    *,
    edition_count: int,
    review_count: int = 0,
    rating_count: int = 0,
) -> bool:
    if any(e.cover_url for e in work.editions):
        return True
    if work.description and len(work.description.strip()) >= MIN_DESCRIPTION_CHARS:
        return True
    return bool(review_count or rating_count or edition_count >= 2)


def author_is_indexable(author: Author, work_count: int) -> bool:
    """A bio, or enough of a bibliography to be worth landing on."""
    return bool((author.bio and author.bio.strip()) or work_count >= 2)


def publisher_is_indexable(edition_count: int) -> bool:
    return edition_count >= 3


# --------------------------------------------------------------------------
# Projection helpers
# --------------------------------------------------------------------------


def _ref(obj) -> P.Ref | None:  # noqa: ANN001
    if obj is None:
        return None
    name = getattr(obj, "pen_name", None) or getattr(obj, "name", None) or ""
    return P.Ref(id=obj.id, name=name, slug=obj.slug, image_url=getattr(obj, "image_url", None))


def _cover(work: Work) -> str | None:
    """The first edition that has one. A book page's LCP element, so the pick
    has to be deterministic rather than 'whatever the DB returned first'."""
    for edition in sorted(work.editions, key=lambda e: (e.created_at, e.id)):
        if edition.cover_url:
            return edition.cover_url
    return None


def card(work: Work, *, rating_count: int = 0, is_original: bool | None = None) -> P.WorkCard:
    return P.WorkCard(
        id=work.id,
        slug=work.slug,
        title=work.title,
        year=work.first_publish_year,
        language=work.language,
        form=work.form,
        rating=work.aggregate_rating,
        rating_count=rating_count,
        cover_url=_cover(work),
        authors=[_ref(a) for a in work.authors],
        is_original=is_original,
    )


def _edition(edition: Edition) -> P.PublicEdition:
    return P.PublicEdition(
        id=edition.id,
        isbn=edition.isbn,
        language=edition.language,
        page_count=edition.page_count,
        pub_date=edition.pub_date,
        year=edition.pub_date.year if edition.pub_date else None,
        format=edition.format,
        cover_url=edition.cover_url,
        back_cover_url=edition.back_cover_url,
        series_number=edition.series_number,
        publisher=_ref(edition.publisher),
        series=_ref(edition.series),
        buy_links=edition.buy_links or [],
    )


def _with_relations(stmt: Select) -> Select:
    return stmt.options(
        selectinload(Work.authors),
        selectinload(Work.editions).selectinload(Edition.publisher),
        selectinload(Work.editions).selectinload(Edition.series),
    )


# --------------------------------------------------------------------------
# Resolution: slug first, UUID as the permanent fallback
# --------------------------------------------------------------------------


async def resolve_including_merged(db: AsyncSession, model: type, key: str):  # noqa: ANN201
    """Find a row even if it was merged away, so the caller can redirect.

    A merged author's old URL must 301 to the survivor, never 404: those URLs
    may be indexed, and a merge that breaks them discards exactly the ranking it
    was meant to consolidate.
    """
    stmt = select(model).where(model.slug == key)
    row = (await db.execute(stmt)).scalars().first()
    if row is None:
        try:
            row = (
                (await db.execute(select(model).where(model.id == uuid.UUID(key))))
                .scalars()
                .first()
            )
        except (ValueError, AttributeError):
            return None
    return row


async def resolve(db: AsyncSession, model: type, key: str):  # noqa: ANN201
    """Find a row by slug, or by UUID when `key` parses as one.

    Both, forever: `/b/<uuid>` links are in Google's index, in every share card
    ever generated, and bound to the app's universal links — and a row whose
    title romanizes to nothing never gets a slug at all.
    """
    stmt = select(model).where(model.deleted_at.is_(None))
    if model is Work:
        stmt = _with_relations(stmt)
    row = (await db.execute(stmt.where(model.slug == key))).scalars().first()
    if row is not None:
        return row
    try:
        as_uuid = uuid.UUID(key)
    except (ValueError, AttributeError):
        return None
    return (await db.execute(stmt.where(model.id == as_uuid))).scalars().first()


async def _rating_counts(db: AsyncSession, work_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """Rating counts for a batch of works in one query — the alternative is one
    query per card in every grid on the site."""
    if not work_ids:
        return {}
    rows = (
        await db.execute(
            select(Rating.work_id, func.count())
            .where(Rating.work_id.in_(work_ids), Rating.deleted_at.is_(None))
            .group_by(Rating.work_id)
        )
    ).all()
    return {work_id: count for work_id, count in rows}


async def _cards(db: AsyncSession, works: list[Work]) -> list[P.WorkCard]:
    counts = await _rating_counts(db, [w.id for w in works])
    return [card(w, rating_count=counts.get(w.id, 0)) for w in works]


# --------------------------------------------------------------------------
# Book page
# --------------------------------------------------------------------------


async def _more_by_author(db: AsyncSession, work: Work, limit: int = 6) -> list[Work]:
    if not work.authors:
        return []
    author_ids = [a.id for a in work.authors]
    stmt = (
        _with_relations(select(Work))
        .join(work_authors, work_authors.c.work_id == Work.id)
        .where(
            work_authors.c.author_id.in_(author_ids),
            Work.id != work.id,
            Work.deleted_at.is_(None),
        )
        .order_by(Work.aggregate_rating.desc().nullslast(), Work.title)
        .limit(limit)
        .distinct()
    )
    return list((await db.execute(stmt)).scalars().unique().all())


async def _related(db: AsyncSession, work: Work, exclude: set[uuid.UUID], limit: int = 6):
    """Books like this one: shared genre first, then same language. Not an
    embedding model — just the signals the catalog already holds, which is
    enough to keep a reader moving and to give the crawler somewhere to go."""
    genre_ids = [g.id for g in work.genres]
    conditions = []
    if genre_ids:
        conditions.append(
            Work.id.in_(select(work_genres.c.work_id).where(work_genres.c.genre_id.in_(genre_ids)))
        )
    if work.language:
        conditions.append(Work.language == work.language)
    if not conditions:
        return []
    stmt = (
        _with_relations(select(Work))
        .where(
            or_(*conditions),
            Work.deleted_at.is_(None),
            Work.id.notin_(exclude | {work.id}),
        )
        .order_by(Work.aggregate_rating.desc().nullslast(), Work.created_at.desc())
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().unique().all())


async def book_page(db: AsyncSession, key: str) -> P.BookPage | None:
    work = await resolve(db, Work, key)
    if work is None:
        return None

    summary = await review_service.rating_summary(db, work.id)
    reviews = await review_service.public_reviews(db, work.id, limit=10)

    siblings = await catalog_service.translation_siblings(db, work)
    original = None
    if work.original_work_id:
        original_row = await resolve(db, Work, str(work.original_work_id))
        original = card(original_row, is_original=True) if original_row else None

    more = await _more_by_author(db, work, limit=6)
    related = await _related(db, work, exclude={w.id for w in more}, limit=6)

    return P.BookPage(
        id=work.id,
        slug=work.slug,
        title=work.title,
        subtitle=work.subtitle,
        description=work.description,
        language=work.language,
        form=work.form,
        first_publish_year=work.first_publish_year,
        authors=[_ref(a) for a in work.authors],
        translators=[_ref(a) for a in work.translators],
        genres=[
            P.Ref(id=g.id, name=g.name, slug=slug_service.slugify(g.name)) for g in work.genres
        ],
        editions=[_edition(e) for e in sorted(work.editions, key=lambda e: (e.created_at, e.id))],
        translations=[card(s, is_original=s.original_work_id is None) for s in siblings],
        original=original,
        translation_group_rating=(
            work.translation_group_rating if hasattr(work, "translation_group_rating") else None
        ),
        rating=P.RatingSummary(
            average=summary["average"],
            count=summary["count"],
            distribution={str(k): v for k, v in (summary["distribution"] or {}).items()},
        ),
        reviews=reviews,
        more_by_author=await _cards(db, more),
        related=await _cards(db, related),
        indexable=work_is_indexable(
            work,
            edition_count=len(work.editions),
            review_count=len(reviews),
            rating_count=summary["count"],
        ),
    )


# --------------------------------------------------------------------------
# Author / publisher / series
# --------------------------------------------------------------------------


async def author_page(db: AsyncSession, key: str) -> P.AuthorPage | None:
    author = await resolve(db, Author, key)
    if author is None:
        return None

    works = await catalog_service.author_works(db, author.id)
    translated = [w for w in works if w.original_work_id is not None]

    publishers: dict[uuid.UUID, Publisher] = {}
    languages: set[str] = set()
    decades: dict[str, int] = {}
    edition_count = 0
    for w in works:
        if w.language:
            languages.add(w.language)
        if w.first_publish_year:
            key_ = f"{(w.first_publish_year // 10) * 10}s"
            decades[key_] = decades.get(key_, 0) + 1
        for e in w.editions:
            edition_count += 1
            if e.publisher is not None:
                publishers[e.publisher.id] = e.publisher

    rated = [w.aggregate_rating for w in works if w.aggregate_rating]
    return P.AuthorPage(
        id=author.id,
        slug=author.slug,
        name=author.name,
        pen_name=author.pen_name,
        bio=author.bio,
        image_url=author.image_url,
        primary_language=author.primary_language,
        on_kitabi=author.linked_user_id is not None,
        works=await _cards(db, works),
        translated_works=await _cards(db, translated),
        publishers=[_ref(p) for p in publishers.values()],
        languages=sorted(languages),
        work_count=len(works),
        edition_count=edition_count,
        rating=round(sum(rated) / len(rated), 2) if rated else None,
        decades=dict(sorted(decades.items())),
        indexable=author_is_indexable(author, len(works)),
    )


async def publisher_page(db: AsyncSession, key: str) -> P.PublisherPage | None:
    publisher = await resolve(db, Publisher, key)
    if publisher is None:
        return None

    works = await catalog_service.publisher_works(db, publisher.id)
    authors: dict[uuid.UUID, Author] = {}
    languages: set[str] = set()
    decades: dict[str, int] = {}
    years: list[int] = []
    edition_count = 0
    for w in works:
        for a in w.authors:
            authors[a.id] = a
        if w.language:
            languages.add(w.language)
        if w.first_publish_year:
            years.append(w.first_publish_year)
            key_ = f"{(w.first_publish_year // 10) * 10}s"
            decades[key_] = decades.get(key_, 0) + 1
        edition_count += sum(1 for e in w.editions if e.publisher_id == publisher.id)

    return P.PublisherPage(
        id=publisher.id,
        slug=publisher.slug,
        name=publisher.name,
        logo_url=publisher.logo_url,
        primary_language=publisher.primary_language,
        works=await _cards(db, works),
        total=len(works),
        authors=[_ref(a) for a in authors.values()],
        languages=sorted(languages),
        edition_count=edition_count,
        earliest_year=min(years) if years else None,
        decades=dict(sorted(decades.items())),
        indexable=publisher_is_indexable(edition_count),
    )


async def series_page(db: AsyncSession, key: str) -> P.SeriesPage | None:
    series = await resolve(db, Series, key)
    if series is None:
        return None
    # One row per work with its position, then join. A plain DISTINCT join
    # can't order by `series_number` — Postgres requires ORDER BY expressions to
    # appear in the select list under SELECT DISTINCT — and grouping first also
    # settles what a book with two editions in the series is numbered.
    positions = (
        select(Edition.work_id, func.min(Edition.series_number).label("position"))
        .where(Edition.series_id == series.id)
        .group_by(Edition.work_id)
        .subquery()
    )
    stmt = (
        _with_relations(select(Work))
        .join(positions, positions.c.work_id == Work.id)
        .where(Work.deleted_at.is_(None))
        .order_by(positions.c.position.asc().nullslast(), Work.first_publish_year.asc())
    )
    works = list((await db.execute(stmt)).scalars().unique().all())
    return P.SeriesPage(
        id=series.id,
        slug=series.slug,
        name=series.name,
        works=await _cards(db, works),
        indexable=len(works) >= 2,
    )


# --------------------------------------------------------------------------
# Home, hubs, browse, search
# --------------------------------------------------------------------------


async def _counts(db: AsyncSession) -> tuple[int, int, int]:
    async def n(model: type) -> int:
        return int(
            await db.scalar(
                select(func.count()).select_from(model).where(model.deleted_at.is_(None))
            )
            or 0
        )

    return await n(Work), await n(Author), await n(Publisher)


async def _language_counts(db: AsyncSession) -> list[P.LanguageCount]:
    rows = (
        await db.execute(
            select(Work.language, func.count())
            .where(Work.deleted_at.is_(None), Work.language.is_not(None))
            .group_by(Work.language)
            .order_by(func.count().desc())
        )
    ).all()
    return [
        P.LanguageCount(name=name, slug=slug_service.slugify(name) or name.lower(), count=count)
        for name, count in rows
    ]


async def _genre_counts(db: AsyncSession) -> list[P.GenreCount]:
    rows = await catalog_service.catalog_genres(db)
    return [
        P.GenreCount(name=name, slug=slug_service.slugify(name) or name.lower(), count=count)
        for name, count in rows
    ]


async def _form_counts(db: AsyncSession) -> list[P.GenreCount]:
    rows = (
        await db.execute(
            select(Work.form, func.count())
            .where(Work.deleted_at.is_(None), Work.form.is_not(None))
            .group_by(Work.form)
            .order_by(func.count().desc())
        )
    ).all()
    return [
        P.GenreCount(name=name, slug=slug_service.slugify(name) or name.lower(), count=count)
        for name, count in rows
    ]


async def _translation_pairs(db: AsyncSession, limit: int = 4) -> list[P.TranslationPair]:
    """Original ↔ translation, both ways — the site's signature module. Only
    pairs where both sides are in the catalog; a dangling half is not a pair."""
    stmt = (
        _with_relations(select(Work))
        .where(Work.original_work_id.is_not(None), Work.deleted_at.is_(None))
        .order_by(Work.aggregate_rating.desc().nullslast(), Work.created_at.desc())
        .limit(limit * 3)
    )
    translations = list((await db.execute(stmt)).scalars().unique().all())
    pairs: list[P.TranslationPair] = []
    for translation in translations:
        original = await resolve(db, Work, str(translation.original_work_id))
        if original is None:
            continue
        pairs.append(
            P.TranslationPair(
                original=card(original, is_original=True),
                translation=card(translation, is_original=False),
            )
        )
        if len(pairs) >= limit:
            break
    return pairs


async def home_page(db: AsyncSession) -> P.HomePage:
    recent = await catalog_service.browse_works(db, 8, 0, sort="year_desc")
    top = list(
        (
            await db.execute(
                _with_relations(select(Work))
                .where(Work.deleted_at.is_(None), Work.aggregate_rating.is_not(None))
                .order_by(Work.aggregate_rating.desc())
                .limit(8)
            )
        )
        .scalars()
        .unique()
        .all()
    )
    # The hero. Prefer something that will actually look good — a cover and a
    # blurb — over merely the highest-rated row, because an empty hero is worse
    # than a less-celebrated one.
    featured_pool = [w for w in (top + recent) if _cover(w) and w.description]
    works, authors, publishers = await _counts(db)
    return P.HomePage(
        featured=card(featured_pool[0]) if featured_pool else (card(top[0]) if top else None),
        recent=await _cards(db, recent),
        top_rated=await _cards(db, top),
        languages=await _language_counts(db),
        genres=await _genre_counts(db),
        translation_pairs=await _translation_pairs(db),
        work_count=works,
        author_count=authors,
        publisher_count=publishers,
    )


def _hub_filters(kind: str, name: str) -> dict:
    if kind == "language":
        return {"languages": [name]}
    if kind == "genre":
        return {"genre": name}
    return {"form": name}


async def _match_name(db: AsyncSession, options: list, slug: str) -> str | None:
    """Hubs are addressed by slug but the catalog stores names, and genres have
    no slug column of their own (a closed vocabulary of a few dozen doesn't earn
    a migration). Match by slugifying what's there."""
    for option in options:
        if option.slug == slug:
            return option.name
    return None


async def hub_page(
    db: AsyncSession,
    kind: str,
    slug: str,
    *,
    form_slug: str | None = None,
    page: int = 1,
    per_page: int = 24,
) -> P.HubPage | None:
    languages = await _language_counts(db)
    genres = await _genre_counts(db)
    forms = await _form_counts(db)

    options = {"language": languages, "genre": genres, "form": forms}[kind]
    name = await _match_name(db, options, slug)
    if name is None:
        return None

    filters = _hub_filters(kind, name)
    form_name = None
    if form_slug:
        form_name = await _match_name(db, forms, form_slug)
        if form_name is None:
            return None
        filters["form"] = form_name

    total = await count_works(db, **filters)
    offset = (page - 1) * per_page
    works = await catalog_service.browse_works(db, per_page, offset, sort="title", **filters)
    start_here = (
        await catalog_service.browse_works(db, 6, 0, sort="year_desc", **filters)
        if page == 1
        else []
    )

    return P.HubPage(
        kind=kind,
        name=name,
        slug=slug,
        form=form_name,
        works=await _cards(db, works),
        start_here=await _cards(db, start_here),
        total=total,
        page=page,
        per_page=per_page,
        languages=languages,
        forms=forms,
        genres=genres,
    )


async def count_works(
    db: AsyncSession,
    *,
    languages: list[str] | None = None,
    form: str | None = None,
    genre: str | None = None,
) -> int:
    """Total for a filtered browse — without it a page can't say "1–24 of 312"
    or offer a last page, and a crawler has no finite set to walk."""
    stmt = select(func.count(func.distinct(Work.id))).where(Work.deleted_at.is_(None))
    if languages:
        stmt = stmt.where(Work.language.in_(languages))
    if form:
        stmt = stmt.where(Work.form == form)
    if genre:
        stmt = (
            stmt.join(work_genres, work_genres.c.work_id == Work.id)
            .join(Genre, Genre.id == work_genres.c.genre_id)
            .where(Genre.name == genre)
        )
    return int(await db.scalar(stmt) or 0)


async def browse_page(
    db: AsyncSession,
    *,
    languages: list[str] | None = None,
    form: str | None = None,
    genre: str | None = None,
    sort: str = "title",
    page: int = 1,
    per_page: int = 24,
) -> P.BrowsePage:
    works = await catalog_service.browse_works(
        db,
        per_page,
        (page - 1) * per_page,
        languages=languages,
        form=form,
        genre=genre,
        sort=sort,
    )
    return P.BrowsePage(
        works=await _cards(db, works),
        total=await count_works(db, languages=languages, form=form, genre=genre),
        page=page,
        per_page=per_page,
        languages=await _language_counts(db),
        forms=await _form_counts(db),
        genres=await _genre_counts(db),
    )


async def search_page(db: AsyncSession, q: str, limit: int = 20) -> P.SearchPage:
    """Full search results, grouped by type and ranked by the same scorer the
    typeahead uses.

    The groups stay (a results page reads better sectioned than interleaved)
    but they are ORDERED BY THEIR BEST MATCH rather than always books-first, and
    each group is sorted by relevance. Searching a publisher's exact name should
    lead with publishers.
    """
    scored = await _candidates(db, q, per_type=limit)
    ranked = search_rank.rank(scored, limit * 3)

    by_kind: dict[str, list[dict]] = {"book": [], "author": [], "publisher": []}
    for item in ranked:
        by_kind[item["kind"]].append(item)

    ids = {
        "book": [i["id"] for i in by_kind["book"]],
        "author": [i["id"] for i in by_kind["author"]],
        "publisher": [i["id"] for i in by_kind["publisher"]],
    }
    work_rows = {w.id: w for w in await _works_by_ids(db, ids["book"])}
    works = [work_rows[i] for i in ids["book"] if i in work_rows]

    # Surface the cross-script hit: the reader typed Latin and got a native
    # script back. Worth saying out loud — it is what makes this search
    # different from everyone else's.
    matched = [w.title for w in works if not w.title.isascii()][:3] if q.isascii() else []

    return P.SearchPage(
        q=q,
        works=await _cards(db, works),
        authors=[
            P.Ref(id=i["id"], name=i["label"], slug=i["slug"], image_url=i.get("image_url"))
            for i in by_kind["author"]
        ],
        publishers=[
            P.Ref(id=i["id"], name=i["label"], slug=i["slug"]) for i in by_kind["publisher"]
        ],
        total=len(ranked),
        matched_scripts=matched,
        # Which section leads. The group holding the single best result goes
        # first; ties keep books above authors above publishers.
        order=[
            k
            for k, _ in sorted(
                ((k, max((i["score"] for i in v), default=0.0)) for k, v in by_kind.items()),
                key=lambda kv: (-kv[1], {"book": 0, "author": 1, "publisher": 2}[kv[0]]),
            )
            if by_kind[k]
        ],
    )


async def _works_by_ids(db: AsyncSession, ids: list) -> list[Work]:
    if not ids:
        return []
    rows = (
        (await db.execute(_with_relations(select(Work)).where(Work.id.in_(ids))))
        .scalars()
        .unique()
        .all()
    )
    return list(rows)


async def translation_group_page(db: AsyncSession, key: str) -> P.TranslationGroupPage | None:
    """One page for a book across every language, canonical to the original —
    so the group page and the book page never compete for the same query."""
    anchor = await resolve(db, Work, key)
    if anchor is None or anchor.translation_group_id is None:
        return None
    stmt = _with_relations(select(Work)).where(
        Work.translation_group_id == anchor.translation_group_id,
        Work.deleted_at.is_(None),
    )
    members = list((await db.execute(stmt)).scalars().unique().all())
    original = next((w for w in members if w.original_work_id is None), None)
    translations = [w for w in members if w is not original]

    translators: dict[uuid.UUID, Author] = {}
    for w in members:
        for t in w.translators:
            translators[t.id] = t

    counts = await _rating_counts(db, [w.id for w in members])
    rated = [w.aggregate_rating for w in members if w.aggregate_rating]
    return P.TranslationGroupPage(
        group_id=anchor.translation_group_id,
        title=(original or anchor).title,
        original=card(original, is_original=True) if original else None,
        translations=[
            card(w, rating_count=counts.get(w.id, 0), is_original=False) for w in translations
        ],
        translators=[_ref(t) for t in translators.values()],
        group_rating=round(sum(rated) / len(rated), 2) if rated else None,
        group_rating_count=sum(counts.values()),
        description=(original or anchor).description,
    )


async def indexable_work_ids(db: AsyncSession, ids: list[uuid.UUID]) -> set[uuid.UUID]:
    """Which of these works clear the content floor — used by the sitemap so it
    advertises only pages worth landing on."""
    if not ids:
        return set()
    stmt = _with_relations(select(Work)).where(Work.id.in_(ids))
    works = list((await db.execute(stmt)).scalars().unique().all())
    rating_counts = await _rating_counts(db, ids)
    review_rows = (
        await db.execute(
            select(Review.work_id, func.count())
            .where(Review.work_id.in_(ids), Review.deleted_at.is_(None))
            .group_by(Review.work_id)
        )
    ).all()
    review_counts = dict(review_rows)
    return {
        w.id
        for w in works
        if work_is_indexable(
            w,
            edition_count=len(w.editions),
            review_count=review_counts.get(w.id, 0),
            rating_count=rating_counts.get(w.id, 0),
        )
    }


# --------------------------------------------------------------------------
# Reviews, batch lookup, reader profiles
# --------------------------------------------------------------------------


async def reviews_page(
    db: AsyncSession, key: str, *, page: int = 1, per_page: int = 20
) -> P.ReviewsPage | None:
    work = await resolve(db, Work, key)
    if work is None:
        return None
    summary = await review_service.rating_summary(db, work.id)
    everything = await review_service.public_reviews(db, work.id, limit=500)
    start = (page - 1) * per_page
    counts = await _rating_counts(db, [work.id])
    return P.ReviewsPage(
        work=card(work, rating_count=counts.get(work.id, 0)),
        rating=P.RatingSummary(
            average=summary["average"],
            count=summary["count"],
            distribution={str(k): v for k, v in (summary["distribution"] or {}).items()},
        ),
        reviews=[P.PublicReviewOut(**r) for r in everything[start : start + per_page]],
        total=len(everything),
        page=page,
        per_page=per_page,
    )


async def works_by_keys(db: AsyncSession, keys: list[str]) -> list[P.WorkCard]:
    """Cards for a specific set of books, in the order asked for.

    Editorial lists are curated by slug in the renderer, so this is what turns
    "these twelve books, in this order" into one API call instead of twelve.
    Keys that don't resolve are skipped rather than erroring — a list must not
    break because one book was merged away.
    """
    keys = keys[:60]
    if not keys:
        return []

    # ONE query for the whole set, not one per key. The first version resolved
    # each key separately, which meant 55 sequential round trips to the database
    # for a ten-list index page — 8.0s measured, right at the edge renderer's
    # timeout, so /lists intermittently rendered as if no list existed. An N+1
    # inside the endpoint whose entire purpose is to avoid N+1.
    ids: list[uuid.UUID] = []
    for key in keys:
        try:
            ids.append(uuid.UUID(key))
        except (ValueError, AttributeError):
            pass

    match = Work.slug.in_(keys)
    if ids:
        match = or_(match, Work.id.in_(ids))
    rows = list(
        (await db.execute(_with_relations(select(Work)).where(match, Work.deleted_at.is_(None))))
        .scalars()
        .unique()
        .all()
    )

    # Return them in the order asked for — a list is a curated sequence, and the
    # database has no opinion about it.
    by_key: dict[str, Work] = {}
    for row in rows:
        if row.slug:
            by_key[row.slug] = row
        by_key[str(row.id)] = row
    found = [by_key[k] for k in keys if k in by_key]
    return await _cards(db, found)


async def reader_page(db: AsyncSession, username: str) -> P.ReaderPage | None:
    """A public reader profile, by handle.

    Returns None for a reader who has not made their profile public — which the
    router turns into a 404. A private profile must have NO page, not an empty
    one: "this handle exists but you can't see it" is itself a disclosure, and
    the visibility flags exist precisely so the web can honour them (rule 16).
    """
    profile = (
        (
            await db.execute(
                select(Profile).where(
                    func.lower(Profile.username) == username.lower(),
                    Profile.profile_visible.is_(True),
                )
            )
        )
        .scalars()
        .first()
    )
    if profile is None:
        return None

    recent: list[Work] = []
    if profile.library_visible:
        stmt = (
            _with_relations(select(Work))
            .join(Edition, Edition.work_id == Work.id)
            .join(LibraryEntry, LibraryEntry.edition_id == Edition.id)
            .where(LibraryEntry.user_id == profile.id, LibraryEntry.deleted_at.is_(None))
            .order_by(LibraryEntry.updated_at.desc())
            .limit(12)
        )
        recent = list((await db.execute(stmt)).scalars().unique().all())

    return P.ReaderPage(
        id=profile.id,
        username=profile.username,
        display_name=profile.full_name or profile.username or "A reader",
        avatar_url=profile.avatar_url,
        score=(await scoring_service.compute_score(db, profile.id)).get("total", 0),
        books_tracked=len(recent),
        books_finished=0,
        library_visible=profile.library_visible,
        recent=await _cards(db, recent),
    )


# --------------------------------------------------------------------------
# Author / publisher directories, and search typeahead
# --------------------------------------------------------------------------


async def people_page(
    db: AsyncSession, kind: str, *, page: int = 1, per_page: int = 48
) -> P.PeoplePage | None:
    """The /authors and /publishers directories.

    Ordered by how many works they carry, then by name: a directory of 1,190
    authors is useless alphabetically — page one would be initials and typos.
    Putting the substantial ones first makes the first page worth landing on,
    which is also what decides whether it is worth indexing.
    """
    if kind == "authors":
        model, join_table, join_col = Author, work_authors, work_authors.c.author_id
    elif kind == "publishers":
        model, join_table, join_col = Publisher, None, None
    else:
        return None

    if kind == "authors":
        count_col = func.count(func.distinct(join_table.c.work_id)).label("n")
        stmt = (
            select(model, count_col)
            .outerjoin(join_table, join_col == model.id)
            .where(model.deleted_at.is_(None))
            .group_by(model.id)
            .order_by(count_col.desc(), model.name)
        )
    else:
        count_col = func.count(func.distinct(Edition.work_id)).label("n")
        stmt = (
            select(model, count_col)
            .outerjoin(Edition, Edition.publisher_id == model.id)
            .where(model.deleted_at.is_(None))
            .group_by(model.id)
            .order_by(count_col.desc(), model.name)
        )

    total = int(
        await db.scalar(select(func.count()).select_from(model).where(model.deleted_at.is_(None)))
        or 0
    )
    rows = (await db.execute(stmt.offset((page - 1) * per_page).limit(per_page))).all()
    return P.PeoplePage(
        kind=kind,
        people=[
            P.PersonCard(
                id=row[0].id,
                name=getattr(row[0], "pen_name", None) or row[0].name,
                slug=row[0].slug,
                image_url=getattr(row[0], "image_url", None),
                language=row[0].primary_language,
                work_count=int(row[1] or 0),
            )
            for row in rows
        ],
        total=total,
        page=page,
        per_page=per_page,
    )


async def _candidates(db: AsyncSession, q: str, per_type: int = 12) -> list[dict]:
    """Pull the best candidates of each type, then describe them uniformly so
    one scorer can order them together.

    Each type is fetched with its own index-served fuzzy query — those are good
    at *finding* — and relevance across types is decided afterwards by
    `search_rank`, which is good at *ordering*. Conflating the two jobs is what
    produced a list with an exact publisher match sitting fifth.
    """
    qt, qf = translit_of(q), fold_of(q)
    works = (await catalog_service.search_local(db, q))[:per_type]
    authors = await catalog_service.search_authors(db, q, limit=per_type)
    publishers = await catalog_service.search_publishers(db, q, limit=per_type)

    author_counts = await _work_counts_for_authors(db, [a.id for a in authors])
    publisher_counts = await _edition_counts_for_publishers(db, [p.id for p in publishers])

    out: list[dict] = []
    for w in works:
        out.append(
            {
                "kind": "book",
                "id": w.id,
                "slug": w.slug,
                "label": w.title,
                "sub": ", ".join(a.pen_name or a.name for a in w.authors) or None,
                "href": f"/book/{w.slug or w.id}",
                "score": search_rank.score(
                    q,
                    label=w.title,
                    translit=w.title_translit,
                    fold=w.title_fold,
                    query_translit=qt,
                    query_fold=qf,
                    popularity=len(w.editions or []),
                    popularity_ceiling=10,
                ),
                # Books first on an exact tie: most searches here are for books.
                "tie": 0,
            }
        )
    for a in authors:
        name = a.pen_name or a.name
        out.append(
            {
                "kind": "author",
                "id": a.id,
                "slug": a.slug,
                "image_url": a.image_url,
                "label": name,
                "sub": "Author",
                "href": f"/author/{a.slug or a.id}",
                "score": search_rank.score(
                    q,
                    label=name,
                    translit=a.name_translit,
                    fold=a.name_fold,
                    query_translit=qt,
                    query_fold=qf,
                    popularity=author_counts.get(a.id, 0),
                    popularity_ceiling=40,
                ),
                "tie": 1,
            }
        )
    for p in publishers:
        out.append(
            {
                "kind": "publisher",
                "id": p.id,
                "slug": p.slug,
                "label": p.name,
                "sub": "Publisher",
                "href": f"/publisher/{p.slug or p.id}",
                "score": search_rank.score(
                    q,
                    label=p.name,
                    translit=p.name_translit,
                    fold=p.name_fold,
                    query_translit=qt,
                    query_fold=qf,
                    popularity=publisher_counts.get(p.id, 0),
                    popularity_ceiling=200,
                ),
                "tie": 2,
            }
        )
    # Never discard what the matcher found — see search_rank.MATCHER_FLOOR.
    for item in out:
        if item["score"] <= search_rank.WEAK:
            item["score"] = search_rank.MATCHER_FLOOR
    return out


async def _work_counts_for_authors(db: AsyncSession, ids: list) -> dict:
    if not ids:
        return {}
    rows = (
        await db.execute(
            select(work_authors.c.author_id, func.count(work_authors.c.work_id))
            .where(work_authors.c.author_id.in_(ids))
            .group_by(work_authors.c.author_id)
        )
    ).all()
    return dict(rows)


async def _edition_counts_for_publishers(db: AsyncSession, ids: list) -> dict:
    if not ids:
        return {}
    rows = (
        await db.execute(
            select(Edition.publisher_id, func.count(Edition.id))
            .where(Edition.publisher_id.in_(ids), Edition.deleted_at.is_(None))
            .group_by(Edition.publisher_id)
        )
    ).all()
    return dict(rows)


async def suggest(db: AsyncSession, q: str, limit: int = 8) -> P.SuggestPage:
    """Typeahead, ranked across all three types together.

    Cross-script matching carries through, so a Latin query surfaces a
    native-script title — and now ranks it properly rather than merely
    including it somewhere in the list.
    """
    ranked = search_rank.rank(await _candidates(db, q), limit)
    return P.SuggestPage(
        q=q,
        suggestions=[
            P.Suggestion(kind=i["kind"], label=i["label"], sub=i["sub"], href=i["href"])
            for i in ranked
        ],
    )


async def indexable_ids(db: AsyncSession, kind: str, ids: list[uuid.UUID]) -> set[uuid.UUID] | None:
    """Which of these rows clear the content floor for their kind.

    Returns None for a kind with no floor, so the caller can tell "everything
    qualifies" apart from "nothing qualifies" — collapsing those two is how a
    sitemap silently empties itself.
    """
    if not ids:
        return set()
    if kind == "works":
        return await indexable_work_ids(db, ids)

    if kind == "authors":
        rows = (
            await db.execute(
                select(Author.id, Author.bio, func.count(work_authors.c.work_id))
                .outerjoin(work_authors, work_authors.c.author_id == Author.id)
                .where(Author.id.in_(ids))
                .group_by(Author.id)
            )
        ).all()
        return {
            row[0]
            for row in rows
            if author_is_indexable_row(bio=row[1], work_count=int(row[2] or 0))
        }

    if kind == "publishers":
        rows = (
            await db.execute(
                select(Publisher.id, func.count(Edition.id))
                .outerjoin(Edition, Edition.publisher_id == Publisher.id)
                .where(Publisher.id.in_(ids))
                .group_by(Publisher.id)
            )
        ).all()
        return {row[0] for row in rows if publisher_is_indexable(int(row[1] or 0))}

    return None


def author_is_indexable_row(*, bio: str | None, work_count: int) -> bool:
    """Same rule as `author_is_indexable`, from raw columns rather than an ORM
    row — the sitemap works in bulk and must not load 10,000 objects to ask."""
    return bool((bio and bio.strip()) or work_count >= 2)
