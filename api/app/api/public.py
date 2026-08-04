"""Public web router — one endpoint per page type on kitabi.in.

Unauthenticated and strictly read-only: every one of these is rendered by a
Cloudflare Pages Function at the edge and served to anonymous visitors and
crawlers. There is no write path here by design (docs/web-platform-plan.md
rule 2) — every action a visitor might want is a door into the app, which keeps
RLS deny-by-default intact and the public attack surface at zero.

Each response is a whole page in one call, so the edge never has to fan out.
Responses carry cache headers the edge honours; the site is served from cache
to crawlers, because spending a new domain's crawl budget on slow responses is
how 1,400 pages take three months to index instead of three weeks.
"""

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status

from app.api.deps import DbSession
from app.schemas import public as P
from app.services import public_service

router = APIRouter(prefix="/public", tags=["public"])

# Short TTL with a long stale window: a page stays instant even when the entry
# is cold-ish, and refreshes behind the request. Catalog edits reach readers
# within the minute via the purge hook rather than by making everyone wait.
_CACHE = {"Cache-Control": "public, s-maxage=300, stale-while-revalidate=86400"}
_CACHE_SHORT = {"Cache-Control": "public, s-maxage=60, stale-while-revalidate=3600"}


def _not_found(what: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={"code": "not_found", "message": f"{what} not found"},
    )


def _cached(response: Response, headers: dict[str, str]) -> None:
    for key, value in headers.items():
        response.headers[key] = value


@router.get("/home", response_model=P.HomePage)
async def home(db: DbSession, response: Response) -> P.HomePage:
    _cached(response, _CACHE_SHORT)
    return await public_service.home_page(db)


@router.get("/book/{key}", response_model=P.BookPage)
async def book(key: str, db: DbSession, response: Response) -> P.BookPage:
    """`key` is a slug or a UUID — both resolve, permanently. Old `/b/<uuid>`
    links are in Google's index, in every share card ever generated, and bound
    to the app's universal links."""
    page = await public_service.book_page(db, key)
    if page is None:
        raise _not_found("Book")
    _cached(response, _CACHE)
    return page


@router.get("/author/{key}", response_model=P.AuthorPage)
async def author(key: str, db: DbSession, response: Response) -> P.AuthorPage:
    page = await public_service.author_page(db, key)
    if page is None:
        raise _not_found("Author")
    _cached(response, _CACHE)
    return page


@router.get("/publisher/{key}", response_model=P.PublisherPage)
async def publisher(key: str, db: DbSession, response: Response) -> P.PublisherPage:
    page = await public_service.publisher_page(db, key)
    if page is None:
        raise _not_found("Publisher")
    _cached(response, _CACHE)
    return page


@router.get("/series/{key}", response_model=P.SeriesPage)
async def series(key: str, db: DbSession, response: Response) -> P.SeriesPage:
    page = await public_service.series_page(db, key)
    if page is None:
        raise _not_found("Series")
    _cached(response, _CACHE)
    return page


@router.get("/translations/{key}", response_model=P.TranslationGroupPage)
async def translations(key: str, db: DbSession, response: Response) -> P.TranslationGroupPage:
    page = await public_service.translation_group_page(db, key)
    if page is None:
        raise _not_found("Translation group")
    _cached(response, _CACHE)
    return page


@router.get("/hub/{kind}/{slug}", response_model=P.HubPage)
async def hub(
    kind: str,
    slug: str,
    db: DbSession,
    response: Response,
    form: str | None = Query(default=None),
    page: int = Query(default=1, ge=1, le=500),
) -> P.HubPage:
    """Genre, language and form hubs are one template with a different filter —
    the mockups draw them as one page and so does this."""
    if kind not in {"genre", "language", "form"}:
        raise _not_found("Hub")
    result = await public_service.hub_page(db, kind, slug, form_slug=form, page=page)
    if result is None:
        raise _not_found("Hub")
    _cached(response, _CACHE)
    return result


@router.get("/browse", response_model=P.BrowsePage)
async def browse(
    db: DbSession,
    response: Response,
    language: Annotated[list[str] | None, Query()] = None,
    form: str | None = Query(default=None),
    genre: str | None = Query(default=None),
    sort: str = Query(default="title", pattern="^(title|year_desc|year_asc|author)$"),
    page: int = Query(default=1, ge=1, le=500),
) -> P.BrowsePage:
    _cached(response, _CACHE_SHORT)
    return await public_service.browse_page(
        db, languages=language, form=form, genre=genre, sort=sort, page=page
    )


@router.get("/search", response_model=P.SearchPage)
async def search(
    db: DbSession, response: Response, q: str = Query(min_length=1, max_length=200)
) -> P.SearchPage:
    _cached(response, _CACHE_SHORT)
    return await public_service.search_page(db, q)


@router.get("/book/{key}/reviews", response_model=P.ReviewsPage)
async def book_reviews(
    key: str,
    db: DbSession,
    response: Response,
    page: int = Query(default=1, ge=1, le=200),
) -> P.ReviewsPage:
    result = await public_service.reviews_page(db, key, page=page)
    if result is None:
        raise _not_found("Book")
    _cached(response, _CACHE)
    return result


@router.get("/works", response_model=list[P.WorkCard])
async def works(
    db: DbSession,
    response: Response,
    slug: Annotated[list[str] | None, Query()] = None,
) -> list[P.WorkCard]:
    """Cards for a named set of books, in the order asked for.

    Editorial lists are curated by slug in the renderer, so this turns "these
    twelve books, in this order" into one call instead of twelve. Keys that
    don't resolve are skipped — a list must not break because one book was
    merged away."""
    _cached(response, _CACHE)
    return await public_service.works_by_keys(db, slug or [])


@router.get("/reader/{username}", response_model=P.ReaderPage)
async def reader(username: str, db: DbSession, response: Response) -> P.ReaderPage:
    """A reader's public profile, by handle.

    404s for a reader who hasn't made their profile public. Deliberately
    indistinguishable from "no such handle": "this reader exists but is
    private" is itself a disclosure, and the visibility flags exist precisely
    so the public web honours them (feature-map rule 16)."""
    result = await public_service.reader_page(db, username)
    if result is None:
        raise _not_found("Reader")
    _cached(response, _CACHE_SHORT)
    return result


@router.get("/people/{kind}", response_model=P.PeoplePage)
async def people(
    kind: str,
    db: DbSession,
    response: Response,
    page: int = Query(default=1, ge=1, le=200),
) -> P.PeoplePage:
    """The /authors and /publishers directories."""
    result = await public_service.people_page(db, kind, page=page)
    if result is None:
        raise _not_found("Directory")
    _cached(response, _CACHE)
    return result


@router.get("/suggest", response_model=P.SuggestPage)
async def suggest(
    db: DbSession, response: Response, q: str = Query(min_length=1, max_length=80)
) -> P.SuggestPage:
    """Search typeahead. Small and cheap — it runs on a keystroke."""
    _cached(response, _CACHE_SHORT)
    return await public_service.suggest(db, q)
