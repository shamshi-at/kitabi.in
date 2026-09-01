"""The in-console handbook: its markup renderer, and who may read what.

Two things here are load-bearing. `fmt` escapes *before* applying the
handbook's own marks — content is written by us today, but a handbook that is
only safe while every editor remembers to escape is a handbook that will one day
be edited by someone who doesn't. And role filtering is real rather than
cosmetic: a page describing a screen its reader cannot open teaches them to
expect a menu item that will never be there.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from console import handbook


def test_bold_code_and_internal_links_render():
    out = str(handbook.fmt("**Suspend** the `account` from [Readers](/readers)."))
    assert "<b>Suspend</b>" in out
    assert "<code>account</code>" in out
    assert '<a href="/readers">Readers</a>' in out


def test_html_in_the_source_is_escaped_not_rendered():
    out = str(handbook.fmt('<script>alert(1)</script> & "quoted"'))
    assert "<script>" not in out
    assert "&lt;script&gt;" in out
    assert "&amp;" in out


def test_an_offsite_link_keeps_its_label_and_loses_its_href():
    # The handbook has no reason to send an operator off-site, and an operator
    # has every reason to trust a link inside their own admin console.
    out = str(handbook.fmt("[click me](https://evil.example/x)"))
    assert "click me" in out
    assert "href" not in out
    out = str(handbook.fmt("[js](javascript:alert(1))"))
    assert "href" not in out


def test_every_topic_has_a_unique_slug_and_at_least_one_section():
    slugs = [t.slug for t in handbook.TOPICS]
    assert len(slugs) == len(set(slugs))
    for t in handbook.TOPICS:
        assert t.title and t.summary
        assert t.sections, f"{t.slug} has no sections"


def test_every_section_id_is_unique_within_its_topic():
    # Section ids are URL fragments — a duplicate makes one of the two
    # unreachable by link, which is the whole point of anchoring them.
    for t in handbook.TOPICS:
        ids = [s.id for s in t.sections]
        assert len(ids) == len(set(ids)), t.slug


def test_roles_only_ever_widen():
    moderator = {t.slug for t in handbook.visible("moderator")}
    editor = {t.slug for t in handbook.visible("editor")}
    superadmin = {t.slug for t in handbook.visible("super_admin")}
    assert moderator < editor < superadmin
    assert "admins" in superadmin and "admins" not in editor
    assert "promotions" in editor and "promotions" not in moderator
    # Everyone gets the pages about doing the job and about their own account.
    assert {"start", "readers", "audit", "account", "glossary"} <= moderator


def test_a_topics_named_screen_is_a_console_path():
    for t in handbook.TOPICS:
        if t.screen:
            assert t.screen.startswith("/"), t.slug


def test_search_finds_a_topic_by_body_text_and_respects_role():
    hits = [t.slug for t in handbook.search("suspend", "moderator")]
    assert "readers" in hits
    # A moderator searching for a word that only appears in an editor topic
    # gets nothing rather than a page they cannot open.
    assert handbook.search("frequency cap", "moderator") == []
    assert "promotions" in [t.slug for t in handbook.search("frequency cap", "editor")]


def test_search_ignores_a_query_too_short_to_mean_anything():
    assert handbook.search("a", "super_admin") == []
    assert handbook.search("   ", "super_admin") == []
