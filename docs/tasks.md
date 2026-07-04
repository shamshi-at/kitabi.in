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
- [x] CI workflow: `api-ci.yml` (ruff, black, pytest against real Postgres, pip-audit
      advisory, docker build) + `app-ci.yml` (build_runner, analyze, test), each
      scoped with `paths:` filters, mirroring rupee-diary's ci.yml split per directory
- [x] `app/lib/core/theme` updated to Reading Room tokens (done in Phase 1 — triggered
      by the first real screens: sign-in, splash, profile)
- [ ] Local dev docs: `.env` setup, Supabase project creation runbook

## Phase 1 — Auth & profile

- [x] **Create the Supabase project** + enable Google and Apple providers (owner
      action, done 4 Jul 2026 — Google via a Web-application OAuth client, Apple via
      an App ID + Services ID + Sign in with Apple key; see `api/scripts/gen_apple_secret.py`
      for regenerating the Apple OAuth secret, which expires every 6 months)
- [x] **Add `in.kitabi.kitabi://login-callback` (and `in.kitabi.kitabi://**`) to
      Supabase → Authentication → URL Configuration → Redirect URLs** — without
      this, OAuth silently falls back to the default Site URL (`localhost:3000`)
      instead of returning to the app; easy to forget if the project is ever recreated
- [x] Google sign-in code path — browser-redirect `signInWithOAuth`, matches
      rupee-diary's pattern exactly (no native `google_sign_in` dependency) — S1
- [x] Apple sign-in code path — `sign_in_with_apple` + `signInWithIdToken`, button
      shown on iOS only — S1
- [x] `profiles` table + `POST /auth/bootstrap` (idempotent; create-on-first-login) —
      migration 000002, `GET/PATCH/DELETE /me`, 8 passing tests
- [x] App auth flow: splash → sign-in → home; go_router auth guard (`_RouterRefreshNotifier`
      pattern from rupee-diary); Supabase session persisted via a
      `flutter_secure_storage`-backed `LocalStorage` override
- [x] Profile screen shell with visibility toggles (profile/library/reviews) — S12
      `[WIRED]`, all default private, wired to `PATCH /me`
- [x] Sign out + account deletion path (confirm dialog → `DELETE /me` soft-delete →
      sign out) — store requirement

## Phase 2 — Shared catalog (Layer 1)

- [x] **Decide metadata source: OpenLibrary** — zero API key/credential to manage
      (CLAUDE.md rule 8), free, Search + Covers + Books APIs, decent global/regional
      ISBN coverage. Google Books would need a managed key; paid adds a bill. Verified
      live against the real API during development (`api/app/services/openlibrary_client.py`).
      `external_source`/`external_id` columns leave room to add a second source later
      without re-architecting.
- [x] Work vs Edition schema: works, editions, authors, publishers, genres, series
      (+ `series_number`) — migration `000003`, `work_authors`/`work_genres` join
      tables, RLS enabled with zero policies on every table (rule 11)
- [x] Translated-work linking (original ↔ translation) `[WIRED]` — `translation_group_id`
      on Work (shared UUID = same translation group) + `POST /catalog/works/{id}/link-translation`;
      structure + API only, no UI yet. **Decided 5 Jul 2026:** each translation is a
      separate Work with its own independent rating/review pool (not a language variant
      of an Edition) — but `WorkOut.translation_group_rating` computes a *display-only*
      average across every Work in the group at read time, so a book page can show
      "4.2 across all translations" without merging the underlying pools
      (`catalog_service.translation_group_rating`, tested in `test_catalog.py`)
- [x] Catalog search API (title/author/ILIKE, or exact ISBN match) — `GET /catalog/search`;
      cache-on-first-use means once a book is fetched from OpenLibrary it's served from
      our own Postgres on every later search
- [x] ISBN lookup endpoint (local match → OpenLibrary → create-if-missing, idempotent
      on the `editions.isbn` unique constraint) — `GET /catalog/isbn/{isbn}`
- [x] Add/edit book API + app form — S7b: `POST /catalog/works`, `PATCH /catalog/works/{id}`,
      `PATCH /catalog/editions/{id}`; app form covers title, authors, language, series +
      book №, publisher, pages, edition ISBN, format, genre chips + custom genres
- [x] ISBN barcode scanner in app (`mobile_scanner`) — S7; iOS needs 15.5+ deployment
      target (bumped from 14.0) and an `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64`
      Podfile `post_install` hook since Google's MLKit pods ship no arm64 simulator
      slice (real devices and Android are unaffected) — verified on an Android emulator
      against the real API (Apple Silicon + iOS 26 simulators can't build this plugin
      at all; not testable there without an older x86_64-capable runtime)
- [x] Generated "typeset" covers (title/author on colour derived from the book, one
      shared frame for real and generated covers) — `core/widgets/typeset_cover.dart`,
      used everywhere a cover appears; "uploaded" images are just any `cover_url`
      (OpenLibrary's own cover URLs already populate this on ISBN lookup) — no separate
      user-photo-upload endpoint built (would need a Supabase storage bucket, out of
      scope for this phase)
- [x] Aggregate rating field on works `[WIRED]` — nullable column, `[WIRED]` per
      feature-map (computes once Layer 2 ratings exist in Phase 3; not written to yet)
- [x] Author browse endpoint + screen: all catalog works by one author — `GET
      /catalog/authors/{id}`, S4c app screen. Owned/not split deferred: needs the
      personal library (Phase 3), which doesn't exist yet
- [x] Publisher browse endpoint + screen: all catalog works by one publisher — `GET
      /catalog/publishers/{id}`, S4d app screen. Genre-chip filtering deferred for the
      same Phase 3 reason
- [x] Author/publisher names tappable (oxblood tint) wherever they appear — search
      results (S4, catalog-only slice — the personal-library merge is Phase 3/6),
      add/edit form isn't itself a browse source but routes correctly; book page (S6)
      doesn't exist yet (Phase 3), so that leg lands with S6

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
- [x] Railway deploy (API) + envs documented — project `kitabi-api`, config as
      code in `api/railway.json` (Dockerfile builder, `/healthz` healthcheck).
      Env vars set directly in Railway (`DATABASE_URL` = the Supavisor pooler
      string, `SUPABASE_URL`, `ENV=production`, `SCHEDULER_ENABLED=true`).
      Service now connected to `shamshi-at/kitabi.in` (branch `main`) for
      git-based auto-deploy — matches rupee-diary (Root Directory `api` set in
      Railway's dashboard, not CLI-settable); `railway up` no longer needed.
- [x] Custom domain `api.kitabi.in` — Railway custom domain + Cloudflare CNAME
      (`api` → Railway's target, proxied) and TXT ownership-verification record,
      same pattern as rupee-diary's `api.rupeediary.com`. Fallback origin domain:
      `https://kitabi-api-production.up.railway.app`.
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
