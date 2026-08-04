# The author page — a reference page, not a byline

> **The goal:** when someone looks up an Indian author, kitabi.in is where they
> land and where they stop. A page that answers who this person was, what they
> wrote, what they won, and what to read first — with every fact traceable to
> where it came from.
>
> Mockups: [author-mockups.html](author-mockups.html). Platform context:
> [web-platform-plan.md](web-platform-plan.md). Design tokens:
> [screen-design.md](screen-design.md).

---

## 1. Where we are — measured, 4 Aug 2026

| | |
|---|---|
| Live authors | **1,162** |
| With a biography | **239** (21%) |
| With a portrait | 299 (26%) |
| With a language | 1,159 |
| **With an OpenLibrary id** | **1,159 (99.7%)** |
| With 2+ works | 171 |
| Verified as a real reader | 0 |

The page that is live today (checked on `/author/m-t-vasudevan-nair`, rendered at
the edge, `Person` + `BreadcrumbList` + `ItemList` JSON-LD, 750 ms TTFB) already
carries: the name, a portrait and description when we have them, the language, a
works/editions/languages stat row, a **published-by list**, a **decade bar** of
publishing activity, and the grid of works. That is more than a stub — but for
the 79% with no description it is a name over a grid, and *none* of it answers
the questions a reference lookup actually asks: when was this person born, what
did they win, what should I read first, and where did you get that.

**The 99.7% figure is the whole opportunity.** Nearly every author carries an
OpenLibrary key, and OpenLibrary keys are recorded in Wikidata as property P648.
That means authors can be matched to Wikidata **by identifier rather than by
name** — no fuzzy guessing, no wrong-person risk from two people sharing a name.

---

## 2. The sourcing problem, which is the whole problem

A Wikipedia-model page is a claim about a real person. Most of the design effort
belongs here, not in the layout.

### 2.1 What Wikidata actually has

Checked against a real Indic author (Thakazhi Sivasankara Pillai, `Q546044`),
with no API key and no account:

```
born          1912-04-17   …and also 1914  ← two values, see §2.3
died          1999-04-10
birthplace    Q7709356
occupation    6 values
awards        4 values     ← Jnanpith, Sahitya Akademi, …
languages     Malayalam
image         Thakazhi 1.jpg (Wikimedia Commons)
OpenLibrary   OL4578078A, OL10814A
influenced by 1 value
sitelinks     14 Wikipedias — including ml, ta, te, pa
labels        8 languages — including the Malayalam native-script name
```

This is everything the mockups ask for, and it is **CC0** — public domain, no
attribution required, no licence to comply with. It also solves two problems we
already have: **portraits** (Commons images are freely licensed, and 74% of our
authors have none) and **native-script names** (Wikidata labels carry the
Malayalam/Tamil/Bengali spelling, which our catalogue mostly lacks).

Wikipedia *prose* is a separate, weaker source: the REST summary endpoint gives
a clean lead paragraph, but it is **CC BY-SA**, which obliges us to attribute and
to license derivatives alike. Treat it as a quotation with a credit, never as
text we own.

### 2.2 The rule that matters most

> **Never generate biographical facts about a real person with an LLM.**

Not as a fallback, not "to fill the gaps", not with a disclaimer. A hallucinated
death date, award, or controversy about a living writer is defamatory in the
ordinary sense of the word, and this catalogue is full of living writers —
several of whom will eventually verify their own pages through the author-claim
flow that already exists. The cost of one invented fact on a real person's page
is not a bug report, it is a person's reputation.

The acceptable uses of an LLM here are narrow and all downstream of sourced
material: summarising a *fetched* Wikipedia paragraph to length, normalising an
award name to a canonical form, or drafting an editorial "start here" note about
*books* rather than people. Everything factual comes from a source with a URL.

### 2.3 Sources disagree, and the page should say so

Thakazhi's birth year is recorded twice in Wikidata: **1912 and 1914**. That is
not an error to paper over — it is a real disagreement in the record, and it is
exactly what a reference page ought to surface rather than silently resolve.

So every fact is stored **with its provenance**, and the page renders honestly:

- one value, one source → state it
- several sources agreeing → state it
- sources disagreeing → *"born 1912 (some sources say 1914)"*
- nothing → **say nothing at all.** No "Unknown", no "N/A", no empty rows. An
  absent fact is absent; a page that lists what it doesn't know reads as a
  database dump rather than a reference work.

### 2.4 The trust ladder

Where a fact came from decides how it is treated, in this order:

1. **The author themselves.** `author_claims` already exists — an approved claim
   links a Profile to an Author. A verified author correcting their own birth
   year outranks everything. This is a genuine differentiator: Wikipedia
   structurally cannot let subjects edit themselves.
2. **A reader contribution, reviewed.** The `work_revisions` approve/reject
   pattern already exists for books; authors get the same. Wiki-style, moderated.
3. **Wikidata**, by identifier match.
4. **Wikipedia extract**, quoted and attributed.
5. **Our own catalogue** — publishers, languages, decades — computed, not claimed.

---

## 3. The page

Twelve blocks, four of which already exist. Everything below the infobox is
optional and disappears entirely when empty (§2.3).

| # | Block | Source | Today |
|---|---|---|---|
| 1 | **Identity** — portrait, name, native-script name, pen name, dates, one-line description | Wikidata + catalogue | partial — no native name, no dates |
| 2 | **Infobox** — born, died, birthplace, occupations, languages, notable works, awards, identifiers | Wikidata | — |
| 3 | **Lead** — two or three paragraphs | Wikipedia (attributed) or editorial | — |
| 4 | **Awards** — a real timeline, year by year | Wikidata P166 | — |
| 5 | **Books** — everything we hold, sortable | Catalogue | ✅ |
| 6 | **Translated into** — the translation graph | Catalogue | — |
| 7 | **Translated *by* them** — translators get author pages | Catalogue | — |
| 8 | **Publishers** | Catalogue | ✅ |
| 9 | **Career timeline** — first published → last, by decade | Catalogue | ✅ |
| 10 | **Related authors** — contemporaries in the same language, "influenced by" | Wikidata + catalogue | — |
| 11 | **Elsewhere** — Wikipedia, Wikidata, OpenLibrary, VIAF | Wikidata identifiers | — |
| 12 | **Sources** — every fact's provenance, and "improve this page" | Ours | — |

The four that exist are all catalogue-derived — which is the point: the half of
the page we can compute is built, and the half that needs a source is missing.

Two blocks nobody else has: **translated by them** (translators are Author rows
here, so a translator gets a real page with a bibliography — a community that is
chronically uncredited and notably willing to link to things that credit them),
and **the translation graph**, which no general reference site models.

---

## 4. Data model

Four additions. `authors` itself gains only cheap scalars.

```
authors                 + birth_date, death_date, birth_place, description,
                          native_name, wikidata_id, fact_source, facts_synced_at

author_awards           id, author_id, name, year, awarding_body, source, source_url
author_identifiers      id, author_id, scheme, value      (wikidata|viaf|openlibrary|isni)
author_facts            id, author_id, field, value, source, source_url, confidence
```

`author_facts` is what makes §2.3 possible: the disagreeing birth years live
there as two rows with two sources, while `authors.birth_date` holds the one the
page leads with. Without it, "sources disagree" is unrepresentable and the
import has to silently pick a winner.

Dates need a **precision** notion — Wikidata gives `1912-04-17` for one author
and `1914` for another, and rendering the second as "1 January 1914" invents a
day. Store precision alongside (`year` | `month` | `day`) and render to it.

---

## 5. Import

A job (`jobs/enrich_authors.py`), same shape as the slug and cover backfills:

1. Match by **P648 OpenLibrary id** — precise, no name guessing.
2. Fall back to a name search **only** when it returns a single unambiguous hit
   whose description mentions writing. Two candidates → skip and queue for
   review. A wrong match here attaches one person's death date to another.
3. Pull labels, dates, awards, identifiers, Commons image.
4. Never overwrite a verified-author or reviewed-contribution value (§2.4).
5. Record `fact_source` and `facts_synced_at` on every write.

Rate: Wikidata asks for courtesy, not payment. Same trickle as the cover
backfill — a few hundred per hour clears 1,162 authors in an afternoon, and the
job then costs one indexed query per run.

**Licensing obligations, discharged in code, not in a promise:** Wikidata facts
are CC0 and need no credit; Wikipedia prose is CC BY-SA and the page must name
Wikipedia with a link next to any text taken from it; Commons images carry
per-file licences and the credit line must be stored with the image URL at
import time, because it cannot be reconstructed later.

---

## 6. SEO

The `Person` JSON-LD grows the properties that make a rich result:
`birthDate`, `deathDate`, `birthPlace`, `award`, `knowsLanguage`, `jobTitle`,
`image`, and — the important one — **`sameAs`** pointing at Wikipedia, Wikidata,
VIAF and OpenLibrary. `sameAs` is how a search engine reconciles our page with
the entity it already knows, which is what lets a small site appear for a query
about a well-documented person.

The content floor (web-platform-plan §8.3) gets stricter and more useful: an
author page becomes indexable on **a bio or a birth date or an award or ≥2
works**, so an enriched page qualifies where a bare one does not.

---

## 7. Phasing

| Phase | Scope |
|---|---|
| **A0** | Schema: the four additions above, with date precision |
| **A1** | Wikidata enrichment job, matched by identifier |
| **A2** | The page: infobox, awards timeline, sources block, `sameAs` |
| **A3** | Wikipedia lead paragraphs, attributed |
| **A4** | Contribution loop — "improve this page", reusing the revision queue |
| **A5** | Verified authors edit their own page (`author_claims` already exists) |
| **A6** | The same treatment for publishers, then series |

A0–A2 is the substance: it turns 1,162 name-and-grid pages into reference pages,
and it needs no editorial writing at all.

---

## 8. "One stop for all lookups" — what it does and doesn't mean

The aim is worth stating precisely, because the wrong reading of it is a trap.

**It means:** for a book, an author, a publisher, a translator, a series, or a
translation in any of fourteen Indian languages, kitabi.in has a page that
answers the question and is fast, honest about its sources, and better than what
exists. That is achievable, because for most of this catalogue *nothing good
exists* — there is no competitor for a page about a Malayalam publisher or a
Tamil translator.

**It does not mean** competing with Wikipedia on Shakespeare. We hold 18
Shakespeare titles; a Shakespeare page here will never beat Wikipedia's and
should not try. For authors the world already documents, the honest play is to
be the best page about *their books in Indian languages* — which editions exist,
who translated them, which house published them — and to link out for the rest.

The moat is depth in a place nobody else has bothered with, not breadth
everywhere.

---

## 9. Risks

| Risk | Handling |
|---|---|
| **A wrong Wikidata match** attaches one person's life to another | Identifier matching only; ambiguous names skipped, not guessed |
| **A hallucinated fact about a living writer** | §2.2 — LLMs never source biographical facts. Non-negotiable |
| **CC BY-SA text used without credit** | Attribution stored with the text at import, rendered next to it |
| **Stale facts** — a writer dies, the page says otherwise | `facts_synced_at` + periodic re-sync; verified authors can correct directly |
| **Thin enriched pages** — an infobox with two rows | Content floor; empty blocks disappear entirely |
| **Wikidata is wrong** | Every fact links to its source so a reader can check, and "improve this page" is on every page |
