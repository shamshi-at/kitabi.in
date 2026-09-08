"""The recap key grammar — the API's half.

**The other half is `app/lib/features/insights/period.dart` (`recapKeyFor`),
and `app/test/recap_key_test.dart` holds the same table.** Keep them in step: a
key the app emits and this parser rejects is a share link that 404s for
everyone the reader sent it to, and a rule with two implementations is how the
app and the app-site-association files came to disagree about which URLs Kitabi
owns (1 Sep 2026).
"""

from datetime import date

import pytest

from app.services import recap_service


# The shared table. Every row is a key the app can emit, paired with the window
# it names — start inclusive, end exclusive, exactly as `rangeFor` builds it.
@pytest.mark.parametrize(
    ("key", "start", "end", "kind"),
    [
        ("2026-09-08", date(2026, 9, 8), date(2026, 9, 9), "day"),
        # Tue 8 Sep 2026 is in ISO week 37, which starts Monday the 7th.
        ("2026-w37", date(2026, 9, 7), date(2026, 9, 14), "week"),
        ("2026-09", date(2026, 9, 1), date(2026, 10, 1), "month"),
        ("2026-08", date(2026, 8, 1), date(2026, 9, 1), "month"),
        # December's end is the January the year rolls into.
        ("2026-12", date(2026, 12, 1), date(2027, 1, 1), "month"),
        ("2026", date(2026, 1, 1), date(2027, 1, 1), "year"),
        ("2025", date(2025, 1, 1), date(2026, 1, 1), "year"),
        ("90d-2026-09-08", date(2026, 6, 10), date(2026, 9, 8), "trailing"),
        ("182d-2026-09-08", date(2026, 3, 10), date(2026, 9, 8), "trailing"),
    ],
)
def test_every_key_the_app_emits_resolves_to_the_window_it_names(key, start, end, kind):
    assert recap_service.parse_recap_key(key) == (start, end, kind)


def test_all_time_starts_at_the_sentinel_the_app_uses():
    """`rangeFor` starts an unbounded window at 2000-01-01. If these two
    disagree, an all-time recap silently drops a reader's oldest sittings."""
    start, _, kind = recap_service.parse_recap_key("all")
    assert (start, kind) == (recap_service.ALL_TIME_START, "all")
    assert recap_service.ALL_TIME_START == date(2000, 1, 1)


def test_a_key_is_case_and_whitespace_insensitive():
    assert recap_service.parse_recap_key("  2026-W37 ") == recap_service.parse_recap_key("2026-w37")


@pytest.mark.parametrize(
    ("key", "why"),
    [
        ("", "empty"),
        ("2026-13", "there is no thirteenth month"),
        ("2026-00", "nor a zeroth"),
        ("2026-02-31", "a date that never happened"),
        ("2026-w00", "ISO weeks start at 1"),
        ("2026-w54", "no year has 54 weeks"),
        ("2025-w53", "2025 has 52 ISO weeks, so this one never happened"),
        ("1999", "before the sentinel"),
        ("2999", "beyond the bound"),
        ("30d-2026-09-08", "only the two trailing windows the app offers"),
        ("90d-2026-13-08", "a trailing window ending nowhere"),
        ("../../etc/passwd", "not a window"),
        ("2026-09-08T00:00:00Z", "not the wire format"),
    ],
)
def test_nothing_else_resolves(key, why):
    """`/recap/<anything>` is an infinite family of URLs, and each key that
    resolves is an origin computation a crawler can mint. A crawler walking a
    combinatorial space is what turned a 3 MB catalogue into 5.75 GB of metered
    egress in a billing cycle (7 Sep 2026), so the answerable space is finite by
    construction, not by hoping nobody asks."""
    assert recap_service.parse_recap_key(key) is None, why


def test_w53_resolves_only_in_the_years_that_have_one():
    """A year has 52 or 53 ISO weeks — 2026 and 2020 have a 53rd, 2025 and 2027
    do not. A link naming a week that never happened must 404 rather than
    resolve to something plausible."""
    assert recap_service.parse_recap_key("2025-w53") is None
    assert recap_service.parse_recap_key("2027-w53") is None
    assert recap_service.parse_recap_key("2020-w53") == (
        date(2020, 12, 28),
        date(2021, 1, 4),
        "week",
    )
    # 2026's does exist, and it runs into January — which is exactly why the
    # key carries the ISO week-*year* and not the calendar one.
    assert recap_service.parse_recap_key("2026-w53") == (
        date(2026, 12, 28),
        date(2027, 1, 4),
        "week",
    )


def test_the_window_is_cut_on_the_readers_own_calendar():
    """A month is a *local* month. Stored instants are UTC, so IST (+330) means
    the month starts at 18:30 the evening before — otherwise a sitting logged at
    11pm on the 30th lands in next month on the page and this one on the card
    that linked to it."""
    start, end, _ = recap_service.parse_recap_key("2026-09")
    at_start, at_end = recap_service.window_bounds(start, end, 330)
    assert at_start.isoformat() == "2026-08-31T18:30:00+00:00"
    assert at_end.isoformat() == "2026-09-30T18:30:00+00:00"

    # No offset recorded (an older install) falls back to UTC rather than
    # refusing to render.
    naive_start, _ = recap_service.window_bounds(start, end, None)
    assert naive_start.isoformat() == "2026-09-01T00:00:00+00:00"
