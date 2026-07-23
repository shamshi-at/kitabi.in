"""Sitemap router — public XML endpoints (no auth, like the other catalog
GETs) that kitabi.in's /sitemaps/* Pages Function proxies to search engines."""

from fastapi import APIRouter, Response

from app.api.deps import DbSession
from app.services import sitemap_service

router = APIRouter(prefix="/catalog/sitemap", tags=["sitemap"])

_HEADERS = {"Cache-Control": "public, max-age=3600"}


def _xml(body: str) -> Response:
    return Response(content=body, media_type="application/xml", headers=_HEADERS)


@router.get("/index.xml")
async def sitemap_index(db: DbSession) -> Response:
    return _xml(await sitemap_service.build_index(db))


@router.get("/{kind}-{page}.xml")
async def sitemap_page(kind: str, page: int, db: DbSession) -> Response:
    return _xml(await sitemap_service.build_page(db, kind, page))
