"""Shared Jinja environment. `templates.TemplateResponse(request, name, ctx)`
uses the modern (request-first) signature."""

from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path

from fastapi.templating import Jinja2Templates

templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))

#: The operators' clock. A fixed offset rather than a tz-database lookup: India
#: has no DST, and a slim image may not ship tzdata at all (the same reasoning
#: as `routers/promotions.py`, which converts the other way for its date fields).
IST = timezone(timedelta(hours=5, minutes=30), "IST")


def to_ist(value: datetime) -> datetime:
    """An instant on the IST clock. A naive value is read as UTC — every
    timestamp column here is `timestamptz`, so that only guards a hand-built row."""
    return (value if value.tzinfo else value.replace(tzinfo=UTC)).astimezone(IST)


def ist(value: datetime | None, fmt: str = "%-d %b %Y, %H:%M") -> str:
    """`{{ at|ist }}` — a stored UTC instant, drawn in IST. Instants only: a
    plain `date` (a reader's start or finish day) has no time of day to shift
    and must not go through this."""
    return to_ist(value).strftime(fmt) if value else "—"


templates.env.filters["ist"] = ist
