"""Keep api.kitabi.in out of search indexes.

The API is not a website. Nothing here should ever appear in a search result:
its JSON is the app's private wire format, its error bodies leak endpoint
shapes, and an indexed endpoint is free reconnaissance for anyone deciding
where to point a scraper. Same two layers as the admin console — robots.txt
asks crawlers not to fetch, the header stops indexing on any fetch that happens
anyway (an inbound link alone is enough to index a URL that was never crawled).

**Why this cannot deindex kitabi.in**, which is the only real hazard here.
The public site is server-rendered at the edge and the edge never forwards
origin headers — every one of the three paths that touches an API response
builds a fresh `Headers` object:

  * page renders          → functions/_lib/layout.js
  * /sitemaps/:name       → functions/sitemaps/[name].js
  * /img/c cover proxy    → functions/img/c.js

Verified before this shipped: no public page references api.kitabi.in at all
(0 occurrences across the home, book and author pages), and robots.txt
advertises the sitemaps at kitabi.in/sitemaps/index.xml — the host readers and
crawlers actually use — not at this one. So `Disallow: /` here costs the public
site nothing.

The one carve-out is `/.well-known/`, and it is **defensive rather than
load-bearing**: as of 4 Aug 2026 this host serves nothing there (both
apple-app-site-association and assetlinks.json are 404 here and 200 on
kitabi.in, which is the host bound to the app's universal links). It is carved
out anyway because `.well-known` is the reserved namespace for exactly the kind
of file that must stay fetchable — an app-association file, an ACME challenge,
security.txt — and a blanket `Disallow` over it breaks those silently, months
later, in a way nobody connects back to this file.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import PlainTextResponse, Response

# `Allow` before `Disallow` for .well-known: within a group the most specific
# rule wins, but being explicit costs nothing and survives a careless edit.
ROBOTS_TXT = "User-agent: *\nAllow: /.well-known/\nDisallow: /\n"

ROBOTS_HEADER = "noindex, nofollow, noarchive"

_EXEMPT_PREFIX = "/.well-known/"


class NoIndexMiddleware(BaseHTTPMiddleware):
    """Stamp X-Robots-Tag on every API response except /.well-known/."""

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        if not request.url.path.startswith(_EXEMPT_PREFIX):
            response.headers["X-Robots-Tag"] = ROBOTS_HEADER
        return response


async def robots(_: Request) -> PlainTextResponse:
    return PlainTextResponse(ROBOTS_TXT, media_type="text/plain")
