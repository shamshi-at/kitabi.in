"""Every clock time the console draws is on Indian time.

The activity lists were converted on 6 Oct 2026 and the owner came back on the 7th:
*"still audit log is displayed in UTC."* Converting one screen at a time is how
that happens — a screen is only right until the next one is looked at. So this
reads every template: a stored instant is drawn with `|ist`, and the only place a
template may print an hour from `strftime` is a label that says it is UTC (the
hover that shows what was actually stored).

Not covered, deliberately: a bare *date* (`%-d %b %Y`) has no clock to get wrong,
and the day-bucketed tables (buy clicks by day, the dashboard's windows) count in
UTC days and say so — what they bucket is not an instant.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from datetime import UTC, datetime

from console import templating

TEMPLATES = Path(templating.__file__).resolve().parent / "templates"
HOUR_FORMAT = re.compile(r"\.strftime\([^)]*%[HIMS][^)]*\)")


def test_no_template_prints_a_clock_time_without_converting_it():
    offenders = []
    for path in sorted(TEMPLATES.glob("*.html")):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if HOUR_FORMAT.search(line) and "UTC" not in line:
                offenders.append(f"{path.name}:{n}: {line.strip()[:110]}")
    assert not offenders, "a stored instant drawn as UTC:\n" + "\n".join(offenders)


def test_the_filter_is_what_the_templates_use():
    assert templating.templates.env.filters["ist"] is templating.ist
    assert templating.ist(datetime(2026, 10, 6, 11, 45, 26, tzinfo=UTC), "%H:%M:%S") == "17:15:26"
    assert templating.ist(None) == "—"


def test_utc_labelled_hovers_are_the_only_utc_left():
    """The exception is real, not a loophole: every UTC mention next to an hour is
    a `title=` hover or a heading for a UTC-bucketed table."""
    for path in sorted(TEMPLATES.glob("*.html")):
        for line in path.read_text().splitlines():
            if HOUR_FORMAT.search(line) and "UTC" in line:
                assert 'title="' in line, f"{path.name}: {line.strip()[:120]}"
