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
      book №, publisher, pages, edition ISBN, format, genre chips + custom genres.
      **Enhanced (6 Jul 2026):** author & publisher are now dropdown-cum-add-new
      typeaheads backed by `GET /catalog/authors?q=` / `GET /catalog/publishers?q=`
      (authors kept as removable chips, not a comma string); the typeset cover preview
      redraws live as title/author are typed.
      **UX polish (8 Jul 2026, owner feedback):** Format/Language pickers replaced the
      Material `DropdownButton` with a Reading Room bottom-sheet picker (`_SelectField`
      + `_openSelectSheet`), boxes matched to the adjacent text-field height; series
      section grouped into a labelled well with clearer copy ("SERIES NAME" / "WHICH
      BOOK?" + examples); cover slots now open an options sheet (`showCoverActionSheet`)
      — capture has a visible Cancel, and an existing cover can be **adjusted**
      (re-crop/rotate/reframe via `recropUploadImage`, which downloads → re-crops →
      re-uploads) or **removed**, so a mis-tap never forces a capture
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
- [x] Cover-photo extraction for scan-misses (8 Jul 2026, owner request): scan finds
      nothing → "Add manually" now carries the scanned ISBN into the form; once the
      user photographs the covers, a "Fill in from photos" button sends the uploaded
      URLs to `POST /catalog/cover-extract` (Claude vision via the same optional
      `ANTHROPIC_API_KEY` gate as recs — dormant when unset, reads any script incl.
      Malayalam) and prefills **only empty** fields: title, authors, publisher,
      description (new editable form field, persisted on the Work), series, language.
      URL allow-list = our covers bucket only; `extraction_service.py` unit-tested
      with a mocked LLM. **Verified live on a real iPhone 8 Jul 2026** (build 38): full
      pipeline works — capture → freely-resizable crop (aspect lock removed) → upload →
      "Fill in from photos" → prefill. Haiku hallucinated Malayalam titles so
      extraction now uses **Sonnet** (`extraction_model`), which read title/author/
      publisher/back-cover description off a stylised Malayalam cover accurately.
  - [x] Follow-up (8 Jul 2026): **ISBN-from-photo** (best-effort) — the model reads the
        13-digit ISBN by the back-cover barcode; `valid_isbn13` gates on the checksum
        (+978/979 prefix) server-side, so a misread digit is dropped rather than
        prefilled (barcode Scan stays the exact path). New `CoverExtractOut.isbn`,
        applied only to an empty field.
  - [x] Follow-up (8 Jul 2026): **attractive extraction loader** — full-screen Reading
        Room overlay (`_ExtractingOverlay`): a gold scan line sweeps the cover over a
        paper scrim, fleuron + "Reading your cover…" + subtitle; reduced-motion holds a
        static line. Verified on the emulator.
- [x] Two field-report fixes (8 Jul 2026, build 42): **duplicate back arrow on the
      book page** — `_BookDetailBody`'s header row carried its own inline `arrow_back`
      IconButton on top of the screen's single floating `_BackButton`; replaced with a
      spacer of the same width so layout is unchanged but there's one control, not two
      (screenshotted on the emulator: confirmed a single clean circle). **Android
      crop-screen tick icon outside the safe area** — `image_cropper`'s `UCropActivity`
      is a legacy-AppCompat Activity that doesn't pad for window insets, and Android
      15 (targetSdk 35) forces edge-to-edge on every Activity, so its toolbar (incl.
      the confirm ✓) drew under the status bar. Added a `UCropTheme` style using the
      API-35 `windowOptOutEdgeToEdgeEnforcement` attribute, scoped to just that
      Activity in the manifest. Verified live on an Android 15 (API 35) emulator —
      pushed a real image through the actual gallery photo picker → UCrop screen →
      toolbar (✕ and ✓) now sit fully below the status bar. AAB build confirms the
      manifest/theme change compiles.
- [x] Fuzzy, ranked global search (8 Jul 2026, owner request): `search_local` /
      `search_authors` / `search_publishers` are now typo-tolerant (`_fuzzy_match`:
      ILIKE + trigram `%` + word-similarity `<%`, all GIN-served; migration `000019`
      adds the publishers index) and relevance-ranked (`_rank` = greatest of
      similarity/word_similarity; works ranked via a grouped id+score pass, then
      eager-loaded in order). ISBN queries stay exact; the CSV import matcher pins
      `fuzzy=False` (it takes the top hit as THE match, so merely-similar books must
      not qualify). App: the search screen keeps the on-device library section
      per-keystroke but debounces the network call 300ms (one request per pause, not
      per key — widget-tested) and `globalSearchProvider` keeps results alive per
      query for instant back-typing; <2-char queries skip the network.
- [x] Typo-tolerant duplicate detection on the add-book form (8 Jul 2026, owner
      request): migration `000018` enables **pg_trgm** + GIN trigram indexes on
      `works.title`/`authors.name`; `GET /catalog/works/similar?title=` ranks
      near-matches by `greatest(similarity, word_similarity)` behind index-served
      predicates (`%`, `<%`, `ILIKE`) — works on any script, Malayalam included.
      App: as the title is typed (create mode only), a 450ms-debounced,
      stale-response-guarded lookup slides a quiet "Already in the catalog?" well
      under the title — tap a match to open that book instead, or ✕ to dismiss for
      the rest of the form. Never a dialog, never an error. Tested end to end
      (pytest against real pg_trgm incl. the 'Chemeen'→'Chemmeen' typo case; widget
      tests for debounce/dismiss/edit-mode-off) and eyeballed on the emulator.

## Phase 3 — Personal library + sync engine (Layer 2)

- [x] Drift schema: library entries, personal tags, reviews, ratings, lending, activity log, sync_queue
      — `app/lib/data/db/tables.dart`, plus `sync_state`/`conflict_history`/`key_values` (device_id) and
      a denormalized `cached_books` table (offline read cache for the shared catalog, populated the
      moment a book is added — CLAUDE.md rule 2)
- [x] Syncable tables on API: `user_id` + soft delete + `server_seq` (SyncableMixin) — migration
      `000004` (`library_entries`, `ratings`, `reviews`, `personal_tags`, `library_entry_tags`,
      `lending_records`, `activity_log_entries`), plus `sync_ops` (push idempotency ledger) and
      `conflict_history`; RLS enabled, zero policies, on every table
- [x] Sync engine: queue → `POST /sync/push` (op UUIDs, idempotent) → `GET /sync/pull?cursor=` —
      ported from rupee-diary (`app/lib/data/sync/sync_engine.dart`,
      `api/app/services/sync_service.py`), scoped by `user_id` alone (no `budget_id`/role checks —
      Kitabi has no cross-user sharing in V1); workmanager 15-min drain + connectivity-triggered sync
- [x] Conflict rules: delete-wins → LWW by server time; conflict history row `[WIRED]`. Kitabi has no
      sharing, so the LWW signal isn't "a different user" (rupee-diary) — it's "a different one of my
      devices" (`device_id`, generated once per install); delete-wins and LWW both write a
      `conflict_history` row, no dedicated viewer screen yet
- [x] Add/remove book to library; reading status (5 states: Pending/Reading/Read/Stopped/Wishlist,
      exact mockup enum) — S5/S6. **Fixed 6 Jul 2026:** the ISBN-scan confirm card's "Add"
      was a no-op (only popped the scanner) — now creates the library entry, caches offline,
      and opens the book. `libraryEntriesProvider` is a reactive Drift stream so adds surface
      immediately on the always-alive home route
- [x] Start/finish dates + reading progress in pages — S6 (start date auto-set on first progress
      entry, finish date auto-set when status → Read, matching the mockup's implicit behavior)
- [x] Personal notes (always private) — S6
- [x] Personal tags / shelves (chips, filterable) — S6 add/remove; S5 grid doesn't yet filter by tag
      (only by status + favourites — tag filter chips on S5 are a small follow-up)
- [x] Favorite flag (gold ribbon) — S5 grid overlay + S6 toggle
- [x] Star rating → attaches to **work** — S6
- [x] Review text + per-review visibility flag (default private); edit/delete — S6
- [x] Dedicated "Rate & review" page (stars + roomy text area + visibility, one save) — the S6
      review card opens it in one tap; marking a book **Read** shows a one-off, self-dismissing
      snackbar prompt ("Finished! What did you think?") only when the book has no rating/review
      yet. Add-book description field gained an "Edit full screen" editor (8 Jul 2026)
- [x] Cover viewer on the book page — tap a cover photo to *view* it full screen (front/back
      swipe, pinch-zoom); editing lives on the camera badge only. kitabi.in/b shows the back
      cover too, with a dependency-free lightbox (8 Jul 2026)
- [x] Post-create confirmation popup on the add-book form — created book's metadata +
      "Add to library" (Adding… → Added ✓) / "Create another" (form reset) / Close (8 Jul 2026)
- [x] Cross-script catalog search — "Kayary" finds "കയർ", "ചെമ്മീൻ" finds "Chemmeen": romanized
      `*_translit` columns (indic-transliteration + anyascii, ORM hooks, migration `000020`,
      GIN trigram indexes), matched by search, typeaheads, and duplicate detection (8 Jul 2026)
- [x] Share card shows freshly photographed covers — uploads capped at 1600px/q85 at the picker
      (uncapped 12MP covers stalled the card preview and got the og:image dropped by messaging
      apps), and Share waits for the cover to decode before rasterising (8 Jul 2026)
- [x] Book page "About this book" section (subtitle + description) with a wiki-style
      "Improve this entry" action opening the catalog edit form (8 Jul 2026)
- [x] Book page redesign — "the Frontispiece" — and the shelf card system, "Grid B"
      (9 Jul 2026, mocked in three directions + a card-system mockup before building,
      owner picked Direction A and Grid B): the book page's hero (`_Frontispiece`) is
      now a gradient wash of the book's own derived colour, a big front+back cover,
      genre eyebrow, serif title, tappable author/publisher, one compact meta line,
      an aggregate rating cluster, then the reader's own stars — a gold-rule "❦"
      divider (`_TheBookDivider`) now separates "your copy" (status/progress/
      review/notes/tags/lending) from the shared catalogue record (about/readers'
      reviews/editions/translations/buy). Every existing section carried over intact.
      New shared `ShelfCover` widget (`core/widgets/shelf_cover.dart`) puts every
      book's state — status pill, reading-progress sliver, favourite ribbon, lent/
      borrowed band — as overlays directly on the cover with no caption row below;
      wired into the library grid (owned + Borrowed) and a public profile's shelf, so
      a book looks identical wherever it's listed. `TypesetCover` gained
      `accentFor`/`tintFor` so the grid and the book page's hero derive the same
      colour from a book's title/author. Also: `PersonLink` (lender/borrower names
      on the book page and lending ledger) now opens a linked user's public profile
      instead of the ledger-only screen — the ledger is still one tap away as the
      profile's default tab; an unlinked private contact still opens the old ledger
      screen since there's no profile to show. Verified live on the emulator
- [x] Reader profile redesign — "the bookplate" (9 Jul 2026, mocked first in
      docs/reader-page-redesign approach): the public profile header is now a gold-inset-
      framed card (Ex Libris eyebrow, gold-ringed avatar, real name) with the @handle
      shown once, in the app bar. Connection state reads as a rotated corner stamp
      (moss "Connected", gold "Waiting…") or, for a stranger/incoming/declined/blocked,
      a single action button inside the plate (Connect / Accept+Deny / Resend / Unblock);
      destructive/rare actions (Disconnect, Block, Cancel) moved into a top-right ⋮ menu.
      Score/Books/Read/Links became a ruled stat row inside the plate; the tabs are now a
      counted segmented control (Ledger · N / Shelf · N). The Shelf search is now
      **advanced** — same 300ms-debounced, transliteration-aware books-only catalog search
      the lend picker uses, unioned by work_id, so a Latin/phonetic query finds a
      Malayalam-titled book on their shelf. Verified live across all connection states
- [x] Lend sheet title now names the book (9 Jul 2026): "Lend this book" → "Lend
      {title}", with "Lend" set apart (italic, oxblood) from the book's own name;
      capped at 2 lines with an ellipsis so an unusually long title can't push the
      borrower/date/note fields or Save button out of view
- [x] Public reviews + connection count (9 Jul 2026): `GET /catalog/works/{id}/reviews`
      returns every reader's *public* review of a book (a naked rating with no public
      review never appears — feature-map.md defers public ratings), paired with that
      same reader's star rating for the book if they left one, and reviewer identity
      resolved fresh on every call — real name/avatar when their profile is public,
      otherwise a stable `User_XXXXXX` placeholder derived from their id (same
      placeholder every time; flips to their real identity on the very next fetch
      once they go public, since nothing is cached/denormalized). New "WHAT READERS
      ARE SAYING" section on the book detail page lists them; a public reviewer's row
      is tappable into `PublicProfileScreen` (send a connection request from there),
      an anonymous one isn't. `GET /users/{id}/profile` gained `connections_count`
      (accepted connections), now a 4th stat cell on the profile's stats card
- [x] Connections + profile polish (9 Jul 2026): the profile's Score/Books/Read counts
      are now a styled card (icon + bold number + caption per cell, hairline dividers)
      instead of plain pills; the tab order flipped to Ledger-first (Shelf second, icon
      changed to `Icons.shelves`, a real bookshelf glyph); the AppBar's global-search icon
      was removed in favor of a search box inside the Shelf tab itself, filtering the
      already-fetched shelf by title/author client-side. Every connection action
      (Accept/Deny/Block, Cancel, Resend, Disconnect/Block, Unblock — not just Connect)
      moved from the Connections list onto the profile page's action row, which now
      renders correctly for every connection state and still works even when the
      profile itself is private (404). The Connections screen is now a plain roster:
      every real account shows its actual avatar photo (API's `GET /connections` gained
      `avatar_url` on `other`) with no inline buttons, just a chevron — tapping any row
      opens the profile where the actions live. Private/unlinked contacts are the one
      exception (still a "Link" button + a direct ledger screen, since they have no
      profile). Verified live on the emulator: Accept moved a request from incoming to
      accepted with no navigation, in real time
- [x] Public profile rework (9 Jul 2026): merged the public profile and the connection's
      lending ledger into one screen instead of a profile that pushed to a second
      ledger screen — Instagram-inspired (AppBar carries only `@username`, the full
      name renders once in the body, an avatar + 3-stat header row, a Connect/Connected
      status pill, and a two-icon Shelf/Ledger tab bar that swaps content inline with
      no navigation). Fixes the literal name duplication between the AppBar title and
      body header. Added a search icon to the AppBar (global catalog search). The
      Connections screen's accepted-card tap now lands directly on this merged screen;
      the redundant separate "view library" icon button was removed. `LoanRow` and the
      counterparty loan filter were extracted from `ConnectionLoansScreen` (still used
      standalone for private/unlinked contacts) so both places share one implementation
- [x] Follow-up UX batch (9 Jul 2026): the lend pick-book sheet's search now unions its
      local substring filter with the books-only catalog search endpoint (transliteration-
      aware, workId-matched), so a cross-script query finds a Malayalam-titled book you own
      the same way global search does; accepted-connection cards in Connections gained a
      "View their library" book-icon button opening `PublicProfileScreen` (shelf grid +
      "View loans") — previously that screen was reachable only through reader search
      (which requires a username), so a connected friend with a public library had no way
      to actually be seen — the missing entry point, not the visibility toggle, was the bug
- [x] 10-item UX batch (9 Jul 2026): disk-cached covers with LRU eviction
      (cached_network_image behind every remote image — no more re-downloads while
      scrolling); wishlist entries get an "I got this book" one-tap move to the shelf;
      the lend pick-book sheet is searchable; the library grid's lending band derives
      from the reactive ledger stream (a lend shows instantly); footer tabs reset to
      their branch root; the ledger header carries global search; global search gains
      a READERS section; the profile screen shows the account picture; profiles are
      public by default (migration `000022`) with public profile + public library
      endpoints and an in-app public reader page (avatar, score, shelf, Connect)
- [x] Home + Insights rework (8 Jul 2026): Home greets by name with a diary-style date,
      shows the newest covers standing on a gold shelf line ("Fresh on your shelf"), a
      reading-goal slip that opens Insights, and a first-run 1-2-3 Scan/Shelve/Lend intro;
      Insights adds avg-pages + most-read-author + longest-book superlatives, a daily
      "Did you know" reading fact, and a fresh-user layout (settable goal ring, fact,
      what-grows-here preview) instead of a bare "no data"
- [x] Lending/connections batch (8 Jul 2026): accepting a connection now backfills the
      loans that predate it (the borrower's shelf used to stay empty forever); Borrowed
      tab counts active loans only; notification taps survive cold start (pending
      external target consumed by the router redirect — also fixes kitabi.in app links);
      Private contacts section in Connections (free-text borrowers, loan counts, "Link"
      to a Kitabi account which re-attaches all their records + sends a request); the
      borrower field offers "Keep as a private contact" explicitly; incoming-request
      badge on the footer Lending item; ledger at-a-glance chips (out/overdue/with you);
      open-loan counts on connection cards; global Search in the bottom nav
- [x] Moderated catalog edits — the contributor's (or an unowned work's) edits apply live;
      anyone else's queue as a `work_revisions` row (migration `000021`, RLS) that the
      contributor approves/rejects from the profile's "Pending edits" inbox; the editor sees
      "Edit sent … will review it". V1 approver = the reader who added the book; proper
      moderation comes with the community layer (8 Jul 2026)
- [x] Personal activity log (finished X, rated Y, added Z) `[WIRED]` — written server-side as a side
      effect of other syncable ops, pulled to the client; no feed UI yet (feature-map.md: "flip it
      public later")
- [x] Library grid UI: covers-first, status pills, lent band — S5. Ticker animation for
      overflowing generated-cover titles built 7 Jul 2026 (`TickerText`: overflow-only, one
      pass on first render with per-book stagger, off under reduced motion, generated
      covers only — mockup `.tick` keyframes)
- [~] Airplane-mode test pass: sync engine logic is thoroughly unit-tested offline (in-memory Drift +
      fake API client — push/pull/conflict/idempotency all covered), and the app boots cleanly on an
      Android emulator with all the new tables/workmanager/providers wired in. **Not yet verified on a
      real device with real airplane mode** — needs a real Google sign-in, which wasn't done in-session
      (see STATUS.md)

## Phase 4 — Lending (the wedge, both directions)

- [x] Lending record model: counterparty free text, lent-on, due-back, returned-at — record, not flag
      (model + sync landed with Phase 3; `borrower_name`/`lent_date`/`due_date`/`returned_date`)
- [ ] Optional `counterparty_user_id` on the lending record + lightweight match (search
      registered users by phone/email/username when recording a lend) `[WIRED→V1]`
- [x] When a lend links to a real user, server mirrors a "borrowed" record onto their
      account (own row, own sync scope, correlated by a shared `linked_loan_id` — not a
      shared row). Kept in step both ways after commit (`lend_mirror_service`): the
      lender's edits/returns/deletes re-mirror onto the borrower's copy, and the
      borrower's "mark returned" reflects `returned_date` back onto the lender's record
      (guarded: only the loan's named `borrower_user_id` can reflect back). Mutations
      sync immediately (repositories fire the sync trigger on every enqueue) and the
      counterparty is nudged by FCM (`lend_new`/`lend_returned`)
- [x] Lending ledger screen, Lent-out tab (out now / returned) — S8. Slice A: reads the
      synced `lending_records` joined to their cached book (`LendingRecordsDao.watchAllActive`,
      reactive `allLendingProvider`), Out-now cards with a computed due stamp (Due in Nd /
      Due {date} / Overdue / No due date) + Mark returned, dimmed Returned section. Home has a
      lending entry point until the Phase 6 bottom nav lands
- [~] Lend flow bottom sheet, with "this person is on Kitabi" match + note — S9. Built the S9
      bottom sheet (to-whom, lent-on, optional due date, note; shared field widgets with the
      log-borrowed sheet). The "on Kitabi" match rides on the cross-user work (Slice D `[WIRED]`)
- [x] Mark returned + "Returned ✓" pill (book detail + ledger)
- [x] Due-date local notification (lending reminder) — S3 nudge. `flutter_local_notifications`
      (+ `timezone`/`flutter_timezone`), on-device only (no push/server, rule 8). Scheduled at
      9am local on the due date when a lend/borrow has one; cancelled on "returned". Native
      config: Android core-library desugaring + POST_NOTIFICATIONS/boot receiver, iOS
      UNUserNotificationCenter delegate. Pure scheduling logic (id/time) unit-tested; **firing
      not yet verified on a real device** (needs a signed-in device run, same standing gap)
- [x] "WITH <NAME>" band on lent covers — S5 (landed with the library grid, see Phase 3's
      grid item; gold band over the cover while a lend is open)
- [~] Borrowed tab: linked entries (auto-created when a lender names you) + self-logged
      entries, in one list — S8b. Slice B: the Borrowed tab is live (With-you-now / Returned,
      self-logged), reading `direction='borrowed'` records that carry the book via `edition_id`
      (no owned library entry). **Linked** (auto-created) entries need the cross-user mirror,
      still to build (Slice D `[WIRED]`)
- [x] "Log a borrowed book" flow: search/scan book, from-whom, borrowed-on, optional
      remind-me date, note — S8c. Bottom sheet with inline catalog search; scan entry deferred
      (search covers it for now)
- [x] "I've returned it" action on borrowed entries (closes your own record; on a
      *linked* borrow the server also reflects the return onto the lender's record —
      no realtime handshake needed, it rides the normal push→mirror→pull loop)
- [x] Per-book lending history on the book page (7 Jul 2026, owner request): the
      lending card lists every loan both ways (`bookLendingHistoryProvider` — lent via
      the entry, borrowed via the edition), newest first, with dates, notes, and
      Returned ✓ / Out now stamps; shows on borrowed-only (unowned) books too.
      Counterparty names everywhere (ledger cards incl. returned/rejected, book page)
      are oxblood doors (`PersonLink`) to the loans-with-that-person page —
      `ConnectionLoansScreen` generalized to match free-text names when there's no
      linked user. Ledger/loan rows' covers+titles and activity-log rows now open the
      book page (activity events resolve entity → edition/work locally).

## Phase 5 — Import (the front door)

- [x] Goodreads CSV parser (shelves, ratings, reviews, dates) — `import_service.parse_csv`
      (Exclusive Shelf → status, `="…"` ISBN unwrap, 0-star → unrated, bookshelves → tags),
      unit-tested
- [x] Generic CSV / Google Sheets export mapping (title column minimum, fuzzy column match) —
      same `parse_csv`, header-alias matching for title/author/isbn/rating/review/status
- [x] Import preview UI (matched rows table) + one-tap import — S2. `POST /import/preview`
      parses + matches; app screen lets you **pick a CSV file** (`file_selector`) or paste it,
      shows matched/unmatched rows, and imports the matched ones into the library
      (status/rating/review), offline-first
- [~] Catalog matching on import (ISBN → title/author fallback; create-if-missing). Match is
      ISBN-exact → title against the local catalog; **create-if-missing for unmatched rows
      (OpenLibrary fetch on import) is a follow-up** — unmatched rows are skipped for now
- [x] CSV export (own data out — trust feature, pairs with import) — `buildLibraryCsv`
      (RFC-4180 quoted, Goodreads-shaped columns) shared from the profile via share_plus

## Phase 6 — Insights & search

- [x] **Bottom-nav shell** (Home · Library · [+] · Lending · Insights) — `StatefulShellRoute`
      with a branch per tab; the centre "+" pushes the add flow. Library/Lending lost their
      back buttons (they're tabs now); detail screens push full-screen over the nav
- [~] Home dashboard: currently reading, lending nudge, shelf counts, one AI pick — S3.
      Built the real S3 dashboard: currently-reading cards with page progress, the gold-edged
      **lending nudge** (soonest-due active lend → tap to the ledger), and the 2×2 shelf-count
      cards (Owned / Read / Lent out / Wishlist). The **AI pick** card is Phase 7
      (recommendations), so it's deliberately not here yet
- [x] Global search: my library first, then catalog — S4. "In your library" matches come
      offline from Drift (`LibraryEntriesDao.search` over the cached-book mirror, by title or
      author) with a status pill → book detail; "In the catalog" from the API. Reached via the
      "+" nav / the search field
- [x] Filter sheet: language, genre, status, year, author/publisher + live count — S4b. Library
      grid (S5) filter sheet: **status**, **language**, **genre** (distinct facets from your
      library), and **favourites-only**, with a **live count** ("Show N books") and an
      active-filter badge; reads a reactive entries⋈books stream (`watchAllWithBooks`) so it
      works offline. Year + author/publisher facets deferred (author/publisher have their own
      browse screens)
- [x] Stats: books/month bars, language donut, pages/month line, status counts — S10. Insights
      screen (dependency-free custom charts): books-read + pages-read + reading-now stats, a
      **books-per-month bar chart**, a **pages-per-month line**, and a **language donut** with
      legend — all from a pure, unit-tested `computeInsights`
- [x] Reading goal ring (personal, e.g. 30 books/year) — S10. Progress ring (read ÷ goal),
      goal stored device-local in `key_values` (default 30, tap to edit)
- [x] Year selector (2026 / 2025 / all time) — S10

## Phase 7 — Recommendations & share

- [x] LLM recommendation service: reasoned from user's ratings, plain-words "why" — S11.
      `GET /recommendations` (auth) → gathers the reader's ratings + catalog candidates
      (excluding owned/rated), asks Claude for picks + a one-line "why", returns `{enabled, picks}`.
      Gated behind an optional `ANTHROPIC_API_KEY` (rule 8: dormant/no external call when unset;
      the owner opts in). LLM call isolated in `_generate_picks`; disabled-path + JSON parsing
      unit-tested. **Live LLM output not yet verified** (no key configured)
- [x] Recs UX: opt-in, visible off switch, + Wishlist / Not for me feedback — S11/S12. Opt-in
      stored device-local (off by default); S11 screen shows picks with a "WHY THIS?" box, an
      always-visible "Turn off", + Wishlist (adds as wishlist) / Not for me (dismiss). Home has
      a quiet "For you" entry card
- [x] Per-book share card generator (any book: cover, title, rating — catalog average if
      you haven't rated it — short blurb, mark, kitabi.in), reachable from the book page
      share icon — S6c. `BookShareCard` rendered to PNG via `RepaintBoundary` + `share_plus`
- [x] Personal-endorsement share card (your rating + review line instead of the blurb) —
      S13; the "Include my rating & note" toggle on S6c folds this into the same card
- [x] Share sheet integration (WhatsApp / Instagram / copy link) — S6c/S13. Uses the OS
      share sheet (WhatsApp/Instagram appear there) + a Copy-link action

## Phase 8 — Platform & launch plumbing

- [x] Version gate: API 426 response + app update screen — `VersionGateMiddleware` compares the
      app's `X-App-Version` header against `min_app_version`, returns 426 with an update payload;
      the Dio client sends the header and surfaces 426 → `updateRequiredProvider` → the router
      locks onto a blocking `UpdateScreen`. Parser + gate + app-side unit-tested
- [x] Supabase keep-warm job (APScheduler, advisory locks) — `keep_warm` runs every 6h under
      `pg_try_advisory_lock` (no double-run across replicas), `SELECT 1` to beat the 7-day idle
      pause. (Lending reminders are client-side local notifications — Phase 4 — so no server job)
- [x] Nightly `pg_dump` → encrypted → R2 backup workflow — `.github/workflows/backup.yml`
      (docker `postgres:16` dump → gzip → GPG AES-256 → R2 via `aws s3`), nightly + manual,
      skips cleanly until the R2/DB secrets are set (owner action before first real user data)
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
- [x] App icons + splash from the Gold Line mark — `flutter_launcher_icons` (full-bleed
      `app_icon.png` source, no pre-baked rounding since the OS applies its own mask;
      Android adaptive icon with an oxblood `#7E2A33` background layer +
      `app_icon_foreground.png`) and `flutter_native_splash` (paper `#F6F0E3` background
      + the existing rounded `kitabi-logo.png` mark, matching `SplashScreen` exactly so
      native → Flutter splash hands off with no color flash). Store listings (Play +
      App Store) still open.
- [ ] Landing page: swap "Launching soon" for real store badges — deferred until store
      listings exist (badges would link nowhere before submission)
- [x] Privacy policy + terms pages (store requirement; landing footer links) — `privacy.html`
      + `terms.html` (Reading Room theme, honest to the app's actual data practices), linked
      from the landing footer and added to the Cloudflare Pages deploy

## Parking lot — v1.5 (designed or deliberately deferred)

- [ ] Quote capture with OCR (regional scripts) — S14 designed
- [ ] Embedding similarity ("books like this")
- [ ] Semantic / mood search
- [ ] Shelf-scan-to-library (camera reads spines)
- [ ] Reading sessions (timed logs)
- [ ] Reading challenges; spoiler-aware companion; AI book insights
- [ ] Web app; email/mobile OTP; community layer (flip the `[WIRED]` switches)
