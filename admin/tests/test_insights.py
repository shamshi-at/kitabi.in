"""The dashboard's chart geometry and deltas.

These are the pure half of `console/insights.py` — everything the live view
draws is decided here, because the console has no build step and therefore no
chart library: the SVG path is computed in Python and printed into the template.
A wrong path is a silently wrong picture, which is worse than a crash, so the
geometry gets real tests even though the queries around it need a database.
"""

import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from console import insights


def test_day_axis_is_dense_oldest_first_and_ends_today():
    axis = insights.day_axis(7, today=date(2026, 9, 1))
    assert len(axis) == 7
    assert axis[0] == date(2026, 8, 26)
    assert axis[-1] == date(2026, 9, 1)
    assert axis == sorted(axis)


def test_fill_turns_a_missing_day_into_a_real_zero():
    # A chart that skips empty days lies about the shape of the curve.
    axis = insights.day_axis(3, today=date(2026, 9, 1))
    values = insights._fill({date(2026, 8, 30): 4, date(2026, 9, 1): 2}, axis)
    assert values == [4, 0, 2]


def test_delta_reports_direction_and_percentage():
    d = insights.delta(120, 100)
    assert d["diff"] == 20 and d["pct"] == 20
    assert d["up"] and not d["down"] and not d["flat"]

    d = insights.delta(80, 100)
    assert d["diff"] == -20 and d["pct"] == -20 and d["down"]

    d = insights.delta(5, 5)
    assert d["flat"] and d["diff"] == 0


def test_delta_from_zero_has_no_percentage():
    # "Up 100%" from nothing is arithmetic, not information — a percentage
    # nobody can act on is worse than an honest blank.
    d = insights.delta(7, 0)
    assert d["pct"] is None
    assert d["diff"] == 7 and d["up"]


def test_spark_spans_the_grid_and_puts_the_peak_at_the_top():
    c = insights.spark([0, 5, 10], height=34)
    xs = [p["x"] for p in c["points"]]
    assert xs == [0.0, 50.0, 100.0]
    # 1px of headroom top and bottom, so the peak is never clipped by the edge.
    assert c["points"][2]["y"] == 1.0
    assert c["points"][0]["y"] == 33.0
    assert c["max"] == 10
    assert c["line"].startswith("M0.0,33.0 L")
    # The area closes down to the baseline and back, or it fills as a ribbon.
    assert c["area"].endswith("Z")
    assert "L100.0,34" in c["area"] and "L0.0,34" in c["area"]


def test_spark_of_all_zeros_draws_a_floor_rather_than_dividing_by_zero():
    c = insights.spark([0, 0, 0])
    assert c["max"] == 0
    assert {p["y"] for p in c["points"]} == {33.0}


def test_spark_of_one_point_centres_it_instead_of_stepping_by_zero():
    c = insights.spark([3])
    assert c["points"][0]["x"] == 50.0


def test_spark_of_nothing_is_empty_not_a_crash():
    c = insights.spark([])
    assert c == {"line": "", "area": "", "points": [], "max": 0}


def test_every_charted_series_has_a_colour_and_a_label():
    keys = {key for key, _, _ in insights.SERIES}
    assert keys <= {"readers", "shelved", "works", "reviews", "editions", "authors", "sessions"}
    for _, label, colour in insights.SERIES:
        assert label and colour.startswith("var(--")


def test_default_range_is_one_of_the_offered_ranges():
    assert insights.DEFAULT_RANGE in insights.RANGES


def test_a_shared_peak_puts_two_series_on_one_scale():
    # The combined growth chart draws four series on one grid. Left to itself
    # each is normalised to its own maximum, so a day with 59 shelvings and a
    # day with 16 reviews both touch the ceiling and the picture says they are
    # equal. `peak` is what stops that.
    big = insights.spark([0, 59], peak=59)
    small = insights.spark([0, 16], peak=59)
    assert big["points"][1]["y"] == 1.0
    assert small["points"][1]["y"] > big["points"][1]["y"]
    assert small["max"] == 59

    # Without it, they land in exactly the same place — the bug this guards.
    assert insights.spark([0, 16])["points"][1]["y"] == big["points"][1]["y"]
