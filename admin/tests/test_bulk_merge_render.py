"""Every catalogue list offers the same way to say "these are the same record".

The console used to have three answers: Works had Keep/Absorb (two rows, ever),
the three name-kinds had nothing on the list at all, and only the moderation
queue could fold N rows into one — which is what "merge every DC Books into one"
actually needs (owner report, 5 Sep 2026).

Rendered, not asserted against the source: a template that forgets the include,
names the wrong kind, or drops the checkbox's data-* payload compiles perfectly
and then does nothing on the screen. No database — the lists are handed their
rows, so stubs are the whole context.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from jinja2 import Environment, FileSystemLoader, StrictUndefined

TEMPLATES = Path(__file__).resolve().parents[1] / "console" / "templates"


class _Row:
    """Enough of a catalogue row for a list template."""

    def __init__(self, name: str, rid: str):
        self.id = rid
        self.name = name
        self.title = name
        self.name_translit = name.lower()
        self.title_translit = name.lower()
        self.primary_language = "Malayalam"
        self.pen_name = None
        self.linked_user_id = None
        self.first_publish_year = 2008
        self.authors = []


class _URL:
    path = "/catalog/publishers"
    query = "q=%E0%B4%A1%E0%B4%BF"


class _Request:
    url = _URL()
    scope: dict = {}


def _env() -> Environment:
    # StrictUndefined: a list that forgets to pass `counts` should fail here,
    # not render a blank column in production.
    env = Environment(loader=FileSystemLoader(str(TEMPLATES)), undefined=StrictUndefined)
    env.globals["url_for"] = lambda *a, **k: "/"
    return env


def _base_ctx() -> dict:
    return {
        "request": _Request(),
        "admin": type("A", (), {"name": "Admin", "role": "editor", "email": "a@b.c"})(),
        # Every counter base.html's rail reads; a missing one is an
        # UndefinedError under StrictUndefined, not a silently blank badge.
        "badges": {
            "claims": 2,
            "merges": 3,
            "reports": 0,
            "revisions": 0,
            "promotions_live": 0,
        },
        "active": "publishers",
        "flash": None,
    }


DC = [
    _Row("DC Books", "11111111-1111-1111-1111-111111111111"),
    _Row("Ḍi Si Buks", "22222222-2222-2222-2222-222222222222"),
    _Row("ഡിസി ബുക്സ്", "33333333-3333-3333-3333-333333333333"),
]
COUNTS = {r.id: n for r, n in zip(DC, (142, 3, 11), strict=False)}


CASES = [
    ("publishers.html", {"rows": DC, "counts": COUNTS, "q": "ഡി സി"}, "publishers"),
    ("authors.html", {"rows": DC, "counts": COUNTS, "q": "ഡി സി", "filter_label": None}, "authors"),
    (
        "series.html",
        {
            "rows": [{"s": r, "count": COUNTS[r.id]} for r in DC],
            "empty_count": 0,
            "q": "ഡി സി",
        },
        "series",
    ),
]


@pytest.mark.parametrize(("template", "extra", "kind"), CASES)
def test_each_list_offers_the_merge_component(template, extra, kind):
    html = _env().get_template(template).render(**_base_ctx(), **extra)

    # The selection the JS hangs off. Without any one of these the bar never
    # appears and the feature is invisible.
    assert "data-bulklist" in html, "the JS scopes on this"
    assert html.count('class="rowchk"') == 3, "one checkbox per row"
    assert "data-selall" in html

    # The dialog, told which engine it is talking to.
    assert f'name="kind" value="{kind}"' in html
    assert 'action="/catalog/bulk-merge"' in html
    assert "data-mergeopen" in html and "data-mergedlg" in html

    # The payload the survivor list is built from — a name and a count per row.
    # Miss these and the panel opens with three blank, tie-less options.
    assert 'data-name="DC Books"' in html
    assert 'data-count="142"' in html
    assert "ഡിസി ബുക്സ്" in html, "the folded spelling must survive rendering"


def test_the_works_list_keeps_delete_beside_merge():
    """Two verbs of very different sharpness on one bar — delete is for rows
    nobody has, merge is for rows readers do."""
    rows = [
        {"w": r, "author": "O. V. Vijayan", "editions": 1, "shelved": 7, "ratings": 5, "reviews": 2}
        for r in DC
    ]
    html = (
        _env()
        .get_template("catalog.html")
        .render(
            **{**_base_ctx(), "active": "catalog"},
            rows=rows,
            q="dharmapuranam",
            gap=None,
            gap_label=None,
            filter_label=None,
            gaps={
                "no_cover": 0,
                "no_desc": 0,
                "no_isbn": 0,
                "no_amazon": 0,
                "no_works_author": 0,
                "no_lang": 0,
                "no_year": 0,
            },
            languages=["Malayalam"],
            forms=["Novel"],
            sort_options={"title": "Title"},
            lang="",
            form="",
            sort="title",
            added_by=None,
            keep="",
        )
    )
    assert 'name="kind" value="works"' in html
    assert "data-bulkdelete" in html
    assert 'form="bulkform"' in html, "the delete button sits outside its form now"
    # Keep/Absorb could only ever pair two rows — that is why it is gone.
    assert "data-mergepick" not in html
    # The counts a work merge is actually judged on.
    assert ">5<" in html and ">2<" in html


def test_the_component_is_written_once():
    """Four lists, one partial. A copy per template is how they drift."""
    src = (TEMPLATES / "_bulk_merge.html").read_text(encoding="utf-8")
    assert "data-mergedlg" in src
    for template in ("publishers.html", "authors.html", "series.html", "catalog.html"):
        body = (TEMPLATES / template).read_text(encoding="utf-8")
        assert "_bulk_merge.html" in body, f"{template} does not include the component"
        assert "data-mergedlg" not in body, f"{template} has its own copy of the dialog"
