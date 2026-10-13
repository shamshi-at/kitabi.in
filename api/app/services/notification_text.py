"""What each reader-to-reader notification says — one table read by both the
push (services/push_service.py) and the in-app inbox (services/inbox_service.py),
so the banner a reader saw and the row they find later can never disagree.

`{title}` is the book's title where the event is about a book. The body is
prefixed with the actor's name by whoever renders it."""

from __future__ import annotations

# type -> (title, body after the actor's name)
TEXTS: dict[str, tuple[str, str]] = {
    "connection_request": ("New connection request", "wants to connect on Kitabi"),
    "connection_accepted": ("Connection accepted", "accepted your connection on Kitabi"),
    "lend_new": ("A book's on its way to you", "lent you “{title}” on Kitabi"),
    "lend_returned": ("Loan marked returned", "marked “{title}” returned"),
    "lend_reminder": ("A gentle nudge", "would like “{title}” back"),
    "borrow_ask": ("Could they borrow it?", "would like to borrow “{title}”"),
}


def render(kind: str, book_title: str | None = None) -> tuple[str, str]:
    """(title, body suffix) for a notification type."""
    title, suffix = TEXTS[kind]
    return title, suffix.format(title=book_title or "a book")
