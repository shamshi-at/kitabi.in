"""A console page is never served from a browser's cache.

Found 6 Oct 2026, from a report on the Buy links worklist: *save a link, the card
leaves — and then the same card is back, with an empty field.* The link was saved
(the audit log has it; several editions were saved two and three times over,
the later link replacing the earlier). What came back was the **page**: the
list removes a saved row in the browser, not on the server, so the HTML the
server sent still has the row; going somewhere and pressing Back hands the
browser's cached copy of that HTML straight back (in a browser: `transferSize:
0`, navigation type `back_forward`), and the card is there again as though
nothing had been saved.

Every page here is a live query and every form changes production, so a cached
page is a wrong page — the same reasoning as `static/sw.js`, which refuses to
cache one for the same reason. `no-store` makes back/forward ask the server
again. HTML only: static files carry their own long-lived headers (their URLs
are versioned), and an endpoint that sets its own `Cache-Control` keeps it.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

NO_STORE = "no-store"


class NoStoreMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        if (
            response.headers.get("content-type", "").startswith("text/html")
            and "cache-control" not in response.headers
        ):
            response.headers["Cache-Control"] = NO_STORE
        return response
