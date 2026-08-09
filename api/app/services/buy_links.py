"""The Amazon buy link, generated from what the catalogue already knows.

Every edition can carry hand-entered `buy_links` (JSONB, wired since the
book-page rework) — but almost nobody enters them, so the buy block sat empty
while the site sent buyers nowhere. This module fills it at READ time: given
an ISBN (failing that, a title), it derives the Amazon.in link and — when an
affiliate tag is configured — tags it so the click pays Kitabi's bills. The
plan this implements is docs/revenue-plan.md §3.1, narrowed on 9 Aug 2026
(owner decision) to **Amazon only**: one recognisable, attractive button
converts better than a row of retailers, and Amazon is the programme we hold
a direct tag for. (Flipkart/Cuelinks generation lived here until then —
see git history if a second retailer ever comes back.)

Three rules:

* **Generated, never stored.** The served link is computed at serialization
  time, so a tag change in config reaches every page on the next request and
  there is no backfill to run or forget. The stored list stays exactly what a
  contributor typed — including non-Amazon links, which are simply not served
  while the one-button policy holds.
* **No credential, no API** (CLAUDE.md rule 8). Amazon's PA-API needs an
  approved account and a key; a `tag=` query parameter needs neither. For most
  printed books the Amazon ASIN *is* the ISBN-10 — `services/isbn.py` already
  derives it — so a direct product link is one string concatenation. 979-boxed
  ISBNs (no ISBN-10 exists) and ISBN-less editions degrade to a search link.
* **Stored links win.** A hand-entered Amazon link (the admin console has a
  per-edition field for exactly this) suppresses the generated one — theirs is
  edition-exact; ours is derived. A stored amazon.in link with no tag still
  gets ours appended, because the page it sits on is ours either way. A link
  that already carries a tag is left alone: overwriting someone's attribution
  is not ours to do.

Pure and dependency-free — no ORM, no I/O, no config import — so the URL
arithmetic is testable directly. Callers pass the affiliate tag in from
Settings; an empty tag means the link renders untagged (the button is still
worth having) and `affiliate` stays False so no disclosure is shown for a
link that pays nobody.
"""

from __future__ import annotations

from urllib.parse import parse_qsl, quote_plus, urlencode, urlsplit, urlunsplit

from app.services import isbn as isbn_service

AMAZON = "Amazon"

# Hostname labels that identify the Amazon family, so a stored short link
# (amzn.to) or foreign marketplace (amazon.com) still counts as "the admin
# entered an Amazon link" and suppresses the generated one.
_AMAZON_LABELS = {"amazon", "amzn"}


def _host(url: str) -> str:
    try:
        return (urlsplit(url).hostname or "").lower()
    except ValueError:  # urlsplit raises on e.g. an unclosed IPv6 bracket
        return ""


def is_amazon(url: str) -> bool:
    """Whether a URL belongs to the Amazon family (any marketplace or short
    link). Public: the admin console's Amazon-link field validates with it."""
    return bool(set(_host(url).split(".")) & _AMAZON_LABELS)


def _search_query(isbn_raw: str | None, title: str, author: str | None) -> str:
    """What to search the store for: the canonical ISBN-13 when one can be
    derived (unambiguous), else title + author. A checksum-invalid ISBN is
    *not* searched — a mis-keyed number matches nothing, or worse, some other
    product; the title at least finds the right shelf."""
    isbn13 = isbn_service.to_isbn13(isbn_raw)
    if isbn13:
        return isbn13
    return f"{title} {author}".strip() if author else title


def _amazon_link(isbn_raw: str | None, title: str, author: str | None, tag: str) -> dict:
    isbn10 = isbn_service.to_isbn10(isbn_raw)
    if isbn10:
        # The ASIN of a printed book is its ISBN-10 — a direct product page.
        url, joiner = f"https://www.amazon.in/dp/{isbn10}", "?"
    else:
        query = quote_plus(_search_query(isbn_raw, title, author))
        url, joiner = f"https://www.amazon.in/s?k={query}", "&"
    if tag:
        url = f"{url}{joiner}tag={quote_plus(tag)}"
    return {"retailer": AMAZON, "url": url, "affiliate": bool(tag)}


def _tag_stored_amazon(url: str, tag: str) -> tuple[str, bool]:
    """Append our tag to a stored amazon.in link that carries none.

    Only amazon.in proper: a short link (amzn.to) goes through Amazon's own
    resolver, which drops parameters we add, and a foreign marketplace
    (amazon.com) belongs to a different Associates programme, so tagging it
    mis-attributes rather than earns. Returns (url, is_ours) — True also when
    the existing tag already is ours, so the disclosure stays truthful."""
    if not tag:
        return url, False
    host = _host(url)
    if host != "amazon.in" and not host.endswith(".amazon.in"):
        return url, False
    parts = urlsplit(url)
    params = parse_qsl(parts.query, keep_blank_values=True)
    if any(key == "tag" for key, _ in params):
        return url, any(key == "tag" and value == tag for key, value in params)
    params.append(("tag", tag))
    return urlunsplit(parts._replace(query=urlencode(params))), True


def merged(
    stored: list | None,
    *,
    isbn: str | None,
    title: str,
    author: str | None,
    amazon_tag: str,
) -> list[dict]:
    """The single link an edition serves: the first stored Amazon-family link
    when one was entered (edition-exact beats derived; tagged where that is
    safe), else one generated from the ISBN. Always returns fresh dicts — the
    JSONB list is never mutated, and its non-Amazon entries are preserved
    there even though they are not served."""
    for entry in stored or []:
        if not isinstance(entry, dict) or not entry.get("url"):
            continue
        url = str(entry["url"])
        if is_amazon(url):
            url, affiliate = _tag_stored_amazon(url, amazon_tag)
            return [{"retailer": AMAZON, "url": url, "affiliate": affiliate}]
    return [_amazon_link(isbn, title, author, amazon_tag)]
