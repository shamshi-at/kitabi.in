"""Who wrote it and who translated it — for books whose shop does not say.

A publisher's storefront credits a book's author, its translator and its
illustrator in one list, the same way, with nothing to tell them apart
(harpercollins.co.in, speakingtigerbooks.com — about a fifth of both shops'
newest books, 3 Oct 2026). The intake gate holds those books for
`author_roles` rather than guess, because a translator published as an author
is wrong data on a public page.

The answer is nearly always on the same page, in prose: *"In Kalpana
Kannabiran's compelling English translation…"*, *"Aboli Mandlik, translator of
Dynasties of Devotion…"*. Reading prose is what a language model is for, so
this asks one — and then **does not take its word for it**.

**An answer is used only if every part of it can be checked against the
publisher's own text**, by plain string matching, here:

- every credited name is given a role, and no other names are;
- each role comes with a quote, and the quote is really in the text;
- the quote is about that person — it is from their own biography, or it
  names them;
- a translator's quote says something about translating, an illustrator's
  about illustrating, an editor's about editing.

Anything short of that and the book stays held, marked as asked, with the
model's reply kept for whoever looks at it. The model is told this is the
deal: `unknown` costs a person a minute; a wrong role is published.

So the model's knowledge of the world is deliberately not used. It may well
know who translated a famous novel — but nothing here could check that, and
"the model was sure" is not a provenance a catalogue can stand on.

**Paid, so metered** (CLAUDE.md: any request that costs money is metered
before it ships): one `llm_quota.consume` at the line the call is made, under
its own feature and daily ceiling and inside the same global breaker as the
reader-facing calls. Dormant without `ANTHROPIC_API_KEY`.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from dataclasses import dataclass

import httpx
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.models import FEATURE_AUTHOR_ROLES, CatalogIntake
from app.models.catalog_intake import STATE_INCOMPLETE
from app.services import intake_gate, intake_service, llm_quota
from app.services.anthropic_client import ANTHROPIC_URL, headers, reply_text

logger = logging.getLogger(__name__)

#: Who the spend is recorded against. `llm_usage` is keyed by reader, and this
#: is not a reader's request — it is the job's. One fixed id, so the job has
#: one daily counter like any account does.
INTAKE_JOB_ID = uuid.UUID(int=0)

#: Thinking cannot be turned off on this model generation and counts towards
#: `max_tokens` together with the reply (CLAUDE.md, 26 Jul 2026), so the budget
#: is sized for both: a short deliberation and a few lines of JSON.
MAX_TOKENS = 4000
TIMEOUT_SECONDS = 90.0
#: The publisher's text sent with a question. A blurb and a few biographies;
#: past this it is a first chapter, and the roles are not in it.
MAX_EVIDENCE = 9000

#: On a policy decline, have the API re-run the request on its recommended
#: fallback model rather than hand back a refusal — a blurb about a war or a
#: virus is still just a blurb. The header is specific to this `"default"` form.
_FALLBACK_BETA = "server-side-fallback-2026-07-01"
_FALLBACK_MODELS = ("claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5")

AUTHOR, TRANSLATOR, ILLUSTRATOR, EDITOR, OTHER, UNKNOWN = (
    "author",
    "translator",
    "illustrator",
    "editor",
    "other",
    "unknown",
)

_SCHEMA = {
    "type": "object",
    "properties": {
        "credits": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "role": {
                        "type": "string",
                        "enum": [AUTHOR, TRANSLATOR, ILLUSTRATOR, EDITOR, OTHER, UNKNOWN],
                    },
                    "evidence": {"type": "string"},
                },
                "required": ["name", "role", "evidence"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["credits"],
    "additionalProperties": False,
}

_SYSTEM = """\
You are helping a book catalogue record who did what on a book.

A publisher's website credits several people for one book and does not say \
what each of them did. One may have written it, another translated it, another \
illustrated it or edited it. You are given the book's title, the credited \
names, and the publisher's own text: its description of the book and, \
sometimes, a biography of each person. Decide each credited person's role from \
that text.

For every credited name, give:
- name: the name exactly as it is credited;
- role: author, translator, illustrator, editor, other (a foreword, an \
introduction, photographs), or unknown;
- evidence: a short phrase copied word for word from the publisher's text that \
shows the role. Copy it exactly as it appears, including its punctuation.

What counts as evidence:
- a phrase about the book that names the person: "In Kalpana Kannabiran's \
English translation", "Deepa Mandlik explores seven ancient temples";
- a phrase from the person's own biography that says what they do: a biography \
that calls someone a translator, or an illustrator, is evidence that this is \
what they did on this book; one that calls them a novelist, a writer or the \
author of other books is evidence that they wrote it.

A phrase taken from anywhere other than the person's own biography has to \
include their name — "his debut novel" does not say whose.

Use only the text you are given. If it does not show what a person did, the \
role is unknown and the evidence is an empty string. Do not work a role out \
from the order of the names, from a name's language or origin, or from what \
you know about the person or the book from elsewhere: your answer is checked \
against the text, phrase by phrase, and an answer that cannot be checked is \
discarded.

Unknown is a perfectly good answer. A book left unknown is looked at by a \
person. A wrong role is published on a public page under someone's name."""


@dataclass(frozen=True)
class Resolution:
    """Who to publish the book under."""

    authors: tuple[str, ...]
    translators: tuple[str, ...] = ()

    def as_facts(self) -> dict:
        return {"authors": list(self.authors), "translators": list(self.translators)}


def enabled(settings: Settings) -> bool:
    return bool(settings.anthropic_api_key)


# --------------------------------------------------------------------------
# Checking an answer against the text — no model involved
# --------------------------------------------------------------------------

#: Curly quotes, dashes and non-breaking spaces, as their plain forms — a quote
#: copied out by a model and the page it came from rarely agree on these.
_QUOTES = str.maketrans(
    {
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u00a0": " ",
        "\u2013": "-",
        "\u2014": "-",
    }
)

#: What a quote has to mention for the role it is offered in support of. An
#: author's quote has no such word — "her landmark novel" and "one of Bengal's
#: best-loved humourists" are both evidence of authorship — so for that role
#: the check is that the quote is real and is about the person.
_ROLE_WORDS = {
    TRANSLATOR: ("translat",),
    ILLUSTRATOR: ("illustrat", "artwork", "art by", "pictures by", "drawings"),
    EDITOR: ("edit", "compil", "curat", "anthology"),
}


def _plain(text: str | None) -> str:
    return " ".join((text or "").translate(_QUOTES).casefold().split())


def _name_words(name: str) -> list[str]:
    """The words of a name worth looking for — not initials."""
    return [w for w in re.findall(r"[^\W\d_]+", name.casefold()) if len(w) >= 3]


def _mentions_another_craft(text: str) -> bool:
    return any(word in text for word in (*_ROLE_WORDS[TRANSLATOR], *_ROLE_WORDS[ILLUSTRATOR]))


def _sentence_around(text: str, quote: str) -> str:
    """The sentence (or sentences) of `text` that `quote` was lifted from."""
    at = text.find(quote)
    if at < 0:
        return quote
    start = max(text.rfind(mark, 0, at) for mark in (". ", "! ", "? ")) + 1
    ends = [i for mark in (". ", "! ", "? ") if (i := text.find(mark, at + len(quote) - 1)) >= 0]
    return text[max(start, 0) : (min(ends) + 1) if ends else len(text)]


def _backed(role: str, name: str, quote: str, blurb: str, bios: dict[str, str]) -> bool:
    """Whether `quote` really is the publisher's text saying `name` did `role`."""
    said = _plain(quote)
    if len(said) < 8:
        return False
    needed = _ROLE_WORDS.get(role)
    if needed and not any(word in said for word in needed):
        return False
    # From this person's own biography: about them by construction.
    own = _plain(bios.get(name))
    if own and said in own:
        # …but a biography that also talks about translating or illustrating
        # cannot settle that they are the *author*. "A full-time writer now"
        # was offered for a book's translator (Desi Disruptors, 4 Oct 2026),
        # out of a biography that goes on to list what he has translated.
        return not (role == AUTHOR and _mentions_another_craft(own))
    # Otherwise it has to be somewhere in the text *and* name them.
    if not any(word in said for word in _name_words(name)):
        return False
    # Each piece of text on its own, so a sentence is never read as running on
    # into the next biography.
    for source in (_plain(text) for text in (blurb, *bios.values())):
        if said in source:
            # Same caution, at the scale of the sentence it was lifted from:
            # "X is a writer" out of "X is a writer and translator" proves
            # nothing.
            return not (role == AUTHOR and _mentions_another_craft(_sentence_around(source, said)))
    return False


def judge(
    answer: object, names: tuple[str, ...], blurb: str, bios: dict[str, str]
) -> Resolution | None:
    """The model's answer, if every part of it stands up; otherwise None.

    Pure: text in, verdict out. This is the function that decides what gets
    published, so it is the one tested hardest.
    """
    credits = answer.get("credits") if isinstance(answer, dict) else None
    if not isinstance(credits, list):
        return None
    roles: dict[str, str] = {}
    for credit in credits:
        if not isinstance(credit, dict):
            return None
        name, role, quote = credit.get("name"), credit.get("role"), credit.get("evidence")
        if name not in names or name in roles or not isinstance(quote, str):
            return None  # a name we did not ask about, or asked about twice
        if role not in (AUTHOR, TRANSLATOR, ILLUSTRATOR, EDITOR, OTHER):
            return None  # unknown — or something that is not a role
        if not _backed(role, name, quote, blurb, bios):
            return None
        roles[name] = role
    if set(roles) != set(names):
        return None  # somebody was left out

    authors = tuple(n for n in names if roles[n] == AUTHOR)
    if not authors:
        # An anthology has editors and no single author; a catalogue files it
        # under the people who made it.
        authors = tuple(n for n in names if roles[n] == EDITOR)
    if not authors:
        return None
    return Resolution(
        authors=authors, translators=tuple(n for n in names if roles[n] == TRANSLATOR)
    )


# --------------------------------------------------------------------------
# Asking
# --------------------------------------------------------------------------


def _question(title: str, names: tuple[str, ...], blurb: str, bios: dict[str, str]) -> str:
    parts = [f"Title: {title}", "", "Credited names:"]
    parts += [f"- {name}" for name in names]
    parts += ["", "The publisher's description of the book:", blurb.strip() or "(none)"]
    for name, bio in bios.items():
        parts += ["", f"The publisher's biography of {name}:", bio.strip()]
    return "\n".join(parts)[:MAX_EVIDENCE]


async def ask(
    client: httpx.AsyncClient,
    settings: Settings,
    *,
    title: str,
    names: tuple[str, ...],
    blurb: str,
    bios: dict[str, str],
) -> object | None:
    """One request: the model's parsed answer, or None when there is none to
    judge (a refusal, a truncated reply, no text). Raises `httpx` errors — the
    caller decides whether that is the end of tonight's asking."""
    model = settings.author_roles_model
    request_headers = headers(settings)
    body: dict = {
        "model": model,
        "max_tokens": MAX_TOKENS,
        # Low: this is reading a paragraph, not solving a problem, and the
        # effort level is also what bounds how much it thinks before answering.
        # `format` makes the reply a JSON object of exactly this shape.
        "output_config": {"effort": "low", "format": {"type": "json_schema", "schema": _SCHEMA}},
        "system": _SYSTEM,
        "messages": [{"role": "user", "content": _question(title, names, blurb, bios)}],
    }
    if model in _FALLBACK_MODELS:
        request_headers["anthropic-beta"] = _FALLBACK_BETA
        body["fallbacks"] = "default"

    response = await client.post(
        ANTHROPIC_URL, headers=request_headers, json=body, timeout=TIMEOUT_SECONDS
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get("stop_reason") in ("refusal", "max_tokens"):
        logger.warning("author_roles: no usable reply (stop_reason=%s)", payload.get("stop_reason"))
        return None
    text = reply_text(payload)
    try:
        return json.loads(text) if text else None
    except ValueError:
        return None


# --------------------------------------------------------------------------
# The nightly pass
# --------------------------------------------------------------------------


async def resolve_held(
    db: AsyncSession, client: httpx.AsyncClient, settings: Settings, *, limit: int
) -> dict[str, int]:
    """Ask about up to `limit` books that are held for author roles and nothing
    else, and release the ones whose answer stands up.

    A book is asked about once. New releases first, like everything else in
    the intake.
    """
    if not enabled(settings) or limit <= 0:
        return {}
    fresh_first = CatalogIntake.payload.has_key(intake_service.FRESH_KEY)  # noqa: W601
    rows = (
        (
            await db.execute(
                select(CatalogIntake)
                .where(
                    CatalogIntake.state == STATE_INCOMPLETE,
                    CatalogIntake.missing.contains([intake_gate.MISSING_AUTHOR_ROLES]),
                    ~CatalogIntake.payload.has_key(intake_service.ROLES_KEY),  # noqa: W601
                )
                .order_by(fresh_first.desc(), CatalogIntake.first_seen_at.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )

    counts: dict[str, int] = {}
    for row in rows:
        if row.missing != [intake_gate.MISSING_AUTHOR_ROLES]:
            continue  # also waiting on a cover or an ISBN: not worth a paid call yet
        payload = row.payload or {}
        names = tuple(payload.get("contributors") or ())
        blurb = payload.get("description") or ""
        page = payload.get(intake_service.PAGE_FACTS_KEY) or {}
        bios = {n: b for n, b in (page.get("bios") or {}).items() if n in names and b}
        if len(names) < 2 or not (blurb or bios):
            # Nothing to read. Marked asked so it is not looked at every night.
            intake_service.apply_roles(row, resolved=None, answer="no publisher text to read")
            counts["nothing_to_read"] = counts.get("nothing_to_read", 0) + 1
            await db.commit()
            continue

        try:
            # Metered at the line the money is spent, after every free return
            # above it. Commits its own reservation.
            await llm_quota.consume(db, INTAKE_JOB_ID, FEATURE_AUTHOR_ROLES, settings=settings)
        except HTTPException:
            logger.info("author_roles: today's ceiling reached — stopping")
            counts["over_budget"] = 1
            break
        try:
            answer = await ask(
                client,
                settings,
                title=payload.get("title") or "",
                names=names,
                blurb=blurb,
                bios=bios,
            )
        except httpx.HTTPError as exc:
            # Our key, their outage, a rate limit: the same for every row
            # after this one, so stop rather than spend the night failing.
            logger.warning("author_roles: request failed (%s) — stopping", type(exc).__name__)
            counts["failed"] = 1
            break

        resolution = judge(answer, names, blurb, bios)
        intake_service.apply_roles(
            row, resolved=resolution.as_facts() if resolution else None, answer=answer
        )
        await db.commit()
        outcome = "resolved" if resolution else "unresolved"
        counts[outcome] = counts.get(outcome, 0) + 1

    return counts
