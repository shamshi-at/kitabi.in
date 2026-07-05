"""Version gate — the app sends its version in `X-App-Version`; a build older
than `min_app_version` gets a 426 Upgrade Required with a structured payload the
app turns into a blocking update screen (CLAUDE.md). Clients that send no header
(curl, the web docs) are let through — the gate targets the mobile app."""

import re

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

from app.core.config import get_settings

_ALWAYS_ALLOW = {"/healthz", "/docs", "/openapi.json"}


def parse_version(value: str) -> tuple[int, ...]:
    """ "1.2.3" -> (1, 2, 3). Missing/garbage parts collapse to (0,)."""
    parts = [int(n) for n in re.findall(r"\d+", value)[:3]]
    return tuple(parts) if parts else (0,)


class VersionGateMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next):  # noqa: ANN001
        if request.url.path not in _ALWAYS_ALLOW:
            client = request.headers.get("x-app-version")
            if client is not None:
                minimum = get_settings().min_app_version
                if parse_version(client) < parse_version(minimum):
                    return JSONResponse(
                        status_code=426,
                        content={
                            "code": "update_required",
                            "message": "Please update Kitabi to continue.",
                            "min_version": minimum,
                        },
                    )
        return await call_next(request)
