"""The recap key grammar — the URL-safe name of a window of reading.

A share card is a picture; `/reader/<handle>/recap/<key>` is the page behind
it, so a recipient can see what the reader actually read in that window (owner
request, 8 Sep 2026). The link carries no secret: it is derived from the
reader's handle and the window, which is what lets the app print it on the card
with no network at all.

This file is only the *rule*, deliberately — the page itself is built in
`public_service.reader_recap`, beside the other public pages. The rule earns
its own file and its own test because it is the half that has a twin:
`recapKeyFor` in `app/lib/features/insights/period.dart` writes these keys and
this reads them, and two implementations of one rule is how the app and the
app-site-association files came to disagree about which URLs Kitabi owns
(1 Sep 2026). `tests/test_recap_key.py` holds the same fixture table its Dart
counterpart does.

Strictness here is not tidiness. `/recap/<anything>` is an infinite family of
URLs, and a crawler walking a combinatorial space is exactly what turned a 3 MB
catalogue into 5.75 GB of metered egress in a billing cycle (7 Sep 2026). Six
shapes resolve, bounded; everything else 404s.
"""

from __future__ import annotations

import re
from datetime import UTC, date, datetime, time, timedelta

# The sentinel the app uses for "all time" — `rangeFor` starts an unbounded
# window at 2000-01-01, and this must agree with it or an all-time recap would
# quietly drop a reader's oldest sittings.
ALL_TIME_START = date(2000, 1, 1)

# The bounds outside which no key resolves. Every distinct key that resolves is
# an origin computation a crawler can mint, so the answerable space is finite.
MIN_YEAR = 2000
MAX_YEAR = 2100

_DAY = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
_WEEK = re.compile(r"^(\d{4})-w(\d{2})$")
_MONTH = re.compile(r"^(\d{4})-(\d{2})$")
_YEAR = re.compile(r"^(\d{4})$")
_TRAILING = re.compile(r"^(90|182)d-(\d{4})-(\d{2})-(\d{2})$")


def parse_recap_key(key: str) -> tuple[date, date, str] | None:
    """`key` → `(start, end, kind)`, start inclusive and end exclusive.

    Returns None for anything unparseable or out of bounds; the router turns
    that into the same 404 a missing handle gets.

        2026-09-08        a day
        2026-w37          an ISO week
        2026-09           a month
        2026              a year
        all               everything
        90d-2026-09-08    the 90 days ending that morning
        182d-2026-09-08   the 182 days ending that morning
    """
    key = key.strip().lower()

    if key == "all":
        # Open-ended on purpose; the caller clamps the end to the reader's own
        # today, since nobody has read tomorrow.
        return ALL_TIME_START, date(MAX_YEAR, 1, 1), "all"

    if m := _TRAILING.match(key):
        days = int(m.group(1))
        end = _date_or_none(int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if end is None:
            return None
        return end - timedelta(days=days), end, "trailing"

    if m := _DAY.match(key):
        day = _date_or_none(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if day is None:
            return None
        return day, day + timedelta(days=1), "day"

    if m := _WEEK.match(key):
        year, week = int(m.group(1)), int(m.group(2))
        if not (MIN_YEAR <= year <= MAX_YEAR) or not 1 <= week <= 53:
            return None
        monday = _iso_week_monday(year, week)
        if monday is None:
            return None
        return monday, monday + timedelta(days=7), "week"

    if m := _MONTH.match(key):
        year, month = int(m.group(1)), int(m.group(2))
        if not (MIN_YEAR <= year <= MAX_YEAR) or not 1 <= month <= 12:
            return None
        start = date(year, month, 1)
        end = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
        return start, end, "month"

    if m := _YEAR.match(key):
        year = int(m.group(1))
        if not MIN_YEAR <= year <= MAX_YEAR:
            return None
        return date(year, 1, 1), date(year + 1, 1, 1), "year"

    return None


def _date_or_none(year: int, month: int, day: int) -> date | None:
    if not MIN_YEAR <= year <= MAX_YEAR:
        return None
    try:
        return date(year, month, day)
    except ValueError:  # 2026-02-31 and friends
        return None


def _iso_week_monday(iso_year: int, iso_week: int) -> date | None:
    """The Monday of ISO week `iso_week` of `iso_year`, or None when that week
    doesn't exist — a year has 52 or 53 of them, and `w53` is real only in some.
    A link naming a week that never happened must 404, not resolve to something
    plausible.
    """
    try:
        return date.fromisocalendar(iso_year, iso_week, 1)
    except ValueError:
        return None


def window_bounds(start: date, end: date, offset_minutes: int | None) -> tuple[datetime, datetime]:
    """The `[start, end)` *local* calendar window as UTC instants.

    Sittings are stored in UTC; the window the reader named is in their own
    local time. Without this a sitting logged at 11pm on the 30th falls in next
    month on the shared page while falling in this one on the card that linked
    to it.
    """
    offset = timedelta(minutes=offset_minutes or 0)
    return (
        datetime.combine(start, time.min, tzinfo=UTC) - offset,
        datetime.combine(end, time.min, tzinfo=UTC) - offset,
    )


def local_today(offset_minutes: int | None) -> date:
    """Today on the reader's own calendar."""
    return (datetime.now(UTC) + timedelta(minutes=offset_minutes or 0)).date()
