# Kitabi — task list

The living checklist. Pick work from here; tick a box **only when** the Definition of
Done is met (code + tests pass, lint clean, migration included if schema changed,
Docker builds, works offline for app features, matches the mockup screen), in the
same commit as the change. If scope shifts, edit this list rather than working
off-list. Screens referenced as S1–S14 (plus lettered sub-screens like S4c, S6c, S8b)
are in [kitabi_screens.html](kitabi_screens.html).

Sources of truth: [feature-map.md](../feature-map.md) (product),
[screen-design.md](screen-design.md) (design), [CLAUDE.md](../CLAUDE.md) (how to build).

---

## Phase 0 — Foundations

- [x] Monorepo root: `landing-page/` · `api/` · `app/` + scoped deploy workflow
- [x] FastAPI scaffold (async SQLAlchemy, JWKS auth, Alembic, tests, Docker)
- [x] Flutter scaffold (Riverpod, go_router, Drift deps, l10n, theme stub)
- [x] Landing page (Reading Room) + logo ("The Gold Line") live at kitabi.in
- [x] Screen mockups S1–S14 + design tokens (feature-map audited, 3 Jul 2026)
- [ ] CI workflow: api (ruff, black, pytest, pip-audit, docker build) + app (analyze, test) with `paths:` filters
- [ ] `app/lib/core/theme` updated to Reading Room tokens (replace landing-page dark seed)
- [ ] Local dev docs: `.env` setup, Supabase project creation runbook

## Phase 1 — Auth & profile

- [ ] Supabase project + Google sign-in (app: supabase_flutter; API: JWKS verify) — S1
- [ ] Apple sign-in — S1
- [ ] `profiles` table + `POST /auth/bootstrap` (create profile on first login)
- [ ] App auth flow: splash → sign-in → home; go_router auth guard; secure token storage
- [ ] Profile screen shell with visibility toggles (profile/library/reviews) — S12 `[WIRED]` all default private
- [ ] Sign out + account deletion path (store requirement)

## Phase 2 — Shared catalog (Layer 1)

- [ ] **Decide metadata source** (OpenLibrary vs Google Books vs paid) — highest-leverage open item
- [ ] Work vs Edition schema: works, editions, authors, publishers, genres, series (+ series №) — migration
- [ ] Translated-work linking (original ↔ translation) `[WIRED]` — structure + API only
- [ ] Catalog search API (title/author/ISBN; metadata-source passthrough + cache-on-first-use)
- [ ] ISBN lookup endpoint (scan → edition match → create-if-missing)
- [ ] Add/edit book API + app form — S7b (series, edition ISBN, format, global genres)
- [ ] ISBN barcode scanner in app (mobile_scanner) — S7
- [ ] Generated "typeset" covers (title/author on colour derived from book) + uploaded cover images, one frame — S5 exhibit
- [ ] Aggregate rating field on works `[WIRED]` (computes; not displayed publicly)
- [ ] Author browse endpoint + screen: all catalog works by one author, split by
      owned/not (reuses the existing add "+"/status-pill row pattern) — S4c
- [ ] Publisher browse endpoint + screen: all catalog works by one publisher, spanning
      authors, chips lean on genre — S4d
- [ ] Author/publisher names tappable (oxblood tint) wherever they appear — search
      results (S4), book page (S6), add/edit form (S7b) — routing to S4c/S4d

## Phase 3 — Personal library + sync engine (Layer 2)

- [ ] Drift schema: library entries, personal tags, reviews, ratings, lending, activity log, sync_queue
- [ ] Syncable tables on API: `user_id` + soft delete + `server_seq` (SyncableMixin) — migration
- [ ] Sync engine: queue → `POST /sync/push` (op UUIDs, idempotent) → `GET /sync/pull?cursor=` — port rupee-diary pattern
- [ ] Conflict rules: delete-wins → LWW by server time; conflict history row `[WIRED]`
- [ ] Add/remove book to library; reading status (5 states) — S5/S6
- [ ] Start/finish dates + reading progress in pages — S6
- [ ] Personal notes (always private) — S6
- [ ] Personal tags / shelves (chips, filterable) — S5
- [ ] Favorite flag (gold ribbon) — S5
- [ ] Star rating → attaches to **work** — S6
- [ ] Review text + per-review visibility flag (default private); edit/delete — S6
- [ ] Personal activity log (finished X, rated Y, added Z) `[WIRED]` — future feed
- [ ] Library grid UI: covers-first, status pills, lent band, ticker for overflowing generated-cover titles — S5
- [ ] Airplane-mode test pass: every feature above works offline and syncs later

## Phase 4 — Lending (the wedge, both directions)

- [ ] Lending record model: counterparty free text, lent-on, due-back, returned-at — record, not flag
- [ ] Optional `counterparty_user_id` on the lending record + lightweight match (search
      registered users by phone/email/username when recording a lend) `[WIRED→V1]`
- [ ] When a lend links to a real user, server mirrors a "borrowed" record onto their
      account (own row, own sync scope, correlated by a shared `linked_loan_id` — not a
      shared row; each side's "mark returned" only closes their own copy, V1 has no
      realtime handshake between the two)
- [ ] Lending ledger screen, Lent-out tab (out now / returned) — S8
- [ ] Lend flow bottom sheet, with "this person is on Kitabi" match + note — S9
- [ ] Mark returned + "Returned ✓" pill
- [ ] Due-date local notification (lending reminder) — S3 nudge
- [ ] "WITH <NAME>" band on lent covers — S5
- [ ] Borrowed tab: linked entries (auto-created when a lender names you) + self-logged
      entries, in one list — S8b
- [ ] "Log a borrowed book" flow: search/scan book, from-whom, borrowed-on, optional
      remind-me date, note — S8c
- [ ] "I've returned it" action on borrowed entries (closes your own record; does not
      require the lender's app state — no realtime sync between the two sides in V1)

## Phase 5 — Import (the front door)

- [ ] Goodreads CSV parser (shelves, ratings, reviews, dates) — service + tests
- [ ] Generic CSV / Google Sheets export mapping (title column minimum, fuzzy column match)
- [ ] Import preview UI (matched rows table) + one-tap import — S2
- [ ] Catalog matching on import (ISBN → title/author fallback; create-if-missing)
- [ ] CSV export (own data out — trust feature, pairs with import)

## Phase 6 — Insights & search

- [ ] Home dashboard: currently reading, lending nudge, shelf counts, one AI pick — S3
- [ ] Global search: my library first, then catalog — S4
- [ ] Filter sheet: language, genre, status, year, author/publisher + live count — S4b
- [ ] Stats: books/month bars, language donut, pages/month line, status counts — S10
- [ ] Reading goal ring (personal, e.g. 30 books/year) — S10
- [ ] Year selector (2026 / 2025 / all time) — S10

## Phase 7 — Recommendations & share

- [ ] LLM recommendation service: reasoned from user's ratings, plain-words "why" — S11
- [ ] Recs UX: opt-in, visible off switch, + Wishlist / Not for me feedback — S11/S12
- [ ] Per-book share card generator (any book: cover, title, rating — catalog average if
      you haven't rated it — short blurb, mark, kitabi.in), reachable from the book page
      share icon and search results — S6c
- [ ] Personal-endorsement share card (your rating + review line instead of the blurb) —
      S13; toggle on S6c folds this in when you have a rating/review for that book
- [ ] Share sheet integration (WhatsApp / Instagram / copy link) — S6c/S13

## Phase 8 — Platform & launch plumbing

- [ ] Version gate: API 426 response + app update screen
- [ ] Supabase keep-warm job + lending-reminder job (APScheduler, advisory locks)
- [ ] Nightly `pg_dump` → encrypted → R2 backup workflow (before first real user data)
- [ ] Railway deploy (API) + envs documented
- [ ] App icons + splash from the Gold Line mark; store listings (Play + App Store)
- [ ] Landing page: swap "Launching soon" for real store badges
- [ ] Privacy policy + terms pages (store requirement; landing footer links)

## Parking lot — v1.5 (designed or deliberately deferred)

- [ ] Quote capture with OCR (regional scripts) — S14 designed
- [ ] Embedding similarity ("books like this")
- [ ] Semantic / mood search
- [ ] Shelf-scan-to-library (camera reads spines)
- [ ] Reading sessions (timed logs)
- [ ] Reading challenges; spoiler-aware companion; AI book insights
- [ ] Web app; email/mobile OTP; community layer (flip the `[WIRED]` switches)
