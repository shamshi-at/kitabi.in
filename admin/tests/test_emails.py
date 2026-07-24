"""The branded email builders return well-formed HTML with a plain-text
alternative, the hosted logo, and properly escaped URLs (a link with query
params must not break out of the href attribute)."""

import sys
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from console import emails

_VOID = {"meta", "img", "br", "hr", "input"}


def _well_formed(html: str) -> bool:
    class P(HTMLParser):
        def __init__(self):
            super().__init__()
            self.stack = []
            self.ok = True

        def handle_starttag(self, tag, attrs):
            if tag not in _VOID:
                self.stack.append(tag)

        def handle_endtag(self, tag):
            if tag in _VOID:
                return
            if self.stack and self.stack[-1] == tag:
                self.stack.pop()
            elif tag in self.stack:
                while self.stack and self.stack.pop() != tag:
                    pass
            else:
                self.ok = False

    p = P()
    p.feed(html)
    return p.ok and not p.stack


def test_reset_email_carries_the_code_in_text_and_html():
    subject, text, html = emails.reset_email("628692", "https://admin.kitabi.in")
    assert "code" in subject.lower()
    assert "628692" in text and "628692" in html
    assert _well_formed(html)
    assert "https://kitabi.in/kitabi-logo.png" in html


def test_magic_email_button_url_is_attribute_escaped():
    subject, text, html = emails.magic_email("https://admin.kitabi.in/magic/AB?x=1&y=2")
    assert "AB?x=1&y=2" in text  # plain text keeps the raw url
    assert "x=1&amp;y=2" in html  # html escapes & inside the href
    assert _well_formed(html)


def test_invite_email_names_the_role():
    subject, text, html = emails.invite_email("https://admin.kitabi.in/invite/TOK", "super_admin")
    assert "super admin" in text and "super admin" in html
    assert _well_formed(html)
