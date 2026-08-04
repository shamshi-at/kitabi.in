"""Keep admin.kitabi.in out of search indexes.

Found on 4 Aug 2026 in Cloudflare's AI Crawl Control: `admin.kitabi.in/graphql/
console` was the single most-crawled path on the whole zone — a scanner probing
for a GraphQL console that doesn't exist. It 404s correctly and nothing was
exposed, but it showed the console is being crawled freely, and until now this
host served no robots.txt at all (a 404) and no noindex on the sign-in page.

An admin login in a search index gains nothing and invites credential stuffing
and targeted phishing. Two layers, because they do different jobs:

  * robots.txt asks well-behaved crawlers not to *fetch*.
  * X-Robots-Tag tells them not to *index* what they did fetch — which matters
    because a page can be indexed from inbound links alone, without ever being
    crawled, and a blanket `Disallow` actually makes that worse: a crawler that
    is forbidden to fetch the page cannot read a `noindex` inside its HTML.
    The header is on the response, so it is read on any fetch that happens.

Neither is access control. Both are advisory, and a hostile scanner ignores
both — the real controls are the session cookie, TOTP, and Cloudflare. This
only stops the console from turning up in a search result.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import PlainTextResponse, Response

ROBOTS_TXT = "User-agent: *\nDisallow: /\n"

# `noindex` — never list this page. `nofollow` — don't walk its links, which on
# an admin console are all deep app routes. `noarchive` — no cached copy, since
# a cached admin page is a snapshot of whatever the crawler happened to see.
ROBOTS_HEADER = "noindex, nofollow, noarchive"


class NoIndexMiddleware(BaseHTTPMiddleware):
    """Stamp X-Robots-Tag on every response this host serves.

    Deliberately unconditional — no path allowlist. Anything reachable here is
    back office, including static assets and error pages, and an exception list
    is a thing that silently rots as routes are added.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        response.headers["X-Robots-Tag"] = ROBOTS_HEADER
        return response


async def robots(_: Request) -> PlainTextResponse:
    return PlainTextResponse(ROBOTS_TXT, media_type="text/plain")
