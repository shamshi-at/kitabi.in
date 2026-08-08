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
- [x] Translated-work linking (original ↔ translation) — `translation_group_id`
      on Work (shared UUID = same translation group) + `POST /catalog/works/{id}/link-translation`.
      **Decided 5 Jul 2026:** each translation is a
      separate Work with its own independent rating/review pool (not a language variant
      of an Edition) — but `WorkOut.translation_group_rating` computes a *display-only*
      average across every Work in the group at read time, so a book page can show
      "4.2 across all translations" without merging the underlying pools
      (`catalog_service.translation_group_rating`, tested in `test_catalog.py`)
- [x] Type & Genre pickers (21 Jul 2026 — mockups M10/M11): the chip rows became
      a **shortcut, not the vocabulary** — capped at 6, selected values pinned
      first, then the reader's own most-used genres (tallied from `cached_books`
      joined to their live library entries, offline), then the common
      suggestions. The honest count beside each label (`All 11 ⌕`) opens a shared
      searchable sheet (`chip_picker_sheet.dart`) holding the whole vocabulary,
      so the form is the same size whether the catalogue carries 10 genres or
      500. `GET /catalog/browse/genres` now returns `{name, work_count}`
      commonest-first, and the sheet shows the count — that's the dedupe
      mechanism, since genres get no server-side case-folding the way Type does,
      and "Science fiction · 128" is what stops "Sci-fi" being born. Creating a
      new value is the dashed last resort and says the genre is shared.
      Replaces the old "＋ Other" dialogs on both rows.
- [x] Translation flows, full UI (21 Jul 2026 — mockups T1–T6 + M1, Areas 8/9):
      **translator credits** (`work_translators` join table, migration `000027`;
      `translator_ids`/`translator_names` on create/patch; `WorkOut.translators`;
      Translator chip field on the add form reusing the author picker; "trans. X"
      byline + sibling-row credit on the book page) · **direction**
      (`works.original_work_id` self-FK; `relation` on link-translation;
      `WorkOut.original` summary; "Translation of …" gold card on a translation's
      page) · **"Translated from" on the add form** (T1/T4: dashed row under
      Language → original-picker T2 with Original/in-group stamps → four-field
      stub sheet T3 with author/type/genre carried over, catalogue-only; links
      the group at create time) · **the original's page** (T6: "＋ Add a
      translation" pre-seeds the add form and links on save, next to "Link
      existing") · **M1 fork** (tapping a similar-title match now asks shelf copy /
      different printing / translation / different book instead of navigating
      away). API covered in `test_catalog.py` (translator create/patch, directed
      links, unresolvable-original ignore)
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
- [x] Personal tags / shelves (chips, filterable) — S6 add/remove; S5 filters by shelf too
      (17 Jul 2026: filter sheet gained a single-select SHELF row, and the grid gained a
      whole Shelves face — tiles per status/Favourites/tag with fanned covers, tap-to-open,
      "+ New shelf" — behind an All books ⇄ Shelves toggle, with search/filter/sort moved
      to the new `ExpandingFab` floating control)
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
- [x] Book page rework, round 2 (9 Jul 2026, mocked and owner-approved before building —
      supersedes the "❦"-divider layout above): fixed a hero tint bug where a muted
      cover (`TypesetCover.tintFor`, e.g. a faded photo-scan cover) washed out to
      nearly nothing — the old version forced lightness to a flat 0.9 while halving
      saturation; now clamps a saturation floor (0.32) and a lower lightness ceiling
      (0.80). Hero gained a solid "spine rail" colour bar on its left edge and a
      filled (solid-background) genre chip. The reader's own star rating moved out of
      the hero entirely into the "MY REVIEW" card, above the review body; the hero
      instead shows the *community* rating (aggregate stars + average + review count,
      live-computed from every `Rating` row on the Work — the old `Work.aggregate_rating`
      column was dead, nothing ever wrote to it) as one plain (no link styling) tap
      target that jumps straight to the About tab. The "❦" divider became a proper
      YOURS / ABOUT segmented tab bar. The old 5-button status row merged into one
      status+progress card with a "Change ›" tap target opening a bottom sheet to
      switch status. Readers' reviews rebuilt: a sort chip (Newest / Highest rated /
      Lowest rated, client-side, no extra fetch), a rating-distribution bar chart
      (average + 5★→1★ bars, from all ratings not just reviewed ones — new
      `PublicReviewsPageOut` API shape wraps `reviews` + `rating_average`/
      `rating_count`/`rating_distribution`), a "no rating" label for star-less
      reviews, and a client-side "Show N more reviews" reveal past the first 5.
      Verified via a targeted widget-test regression (`review_flow_test.dart`) plus
      the existing 70-test suite and `flutter analyze`; the regression test also
      caught and fixed a real `_RatingDistribution` layout bug (5 stars at 14px
      overflowed the old 62px-wide label column by 8px — widened to 78px)
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
- [ ] Author account linking ("This is me") — `authors.linked_user_id` column + migration;
      "This is me" checkbox wired into the existing `create_author` call for a brand-new
      Author, plus a one-tap self-link button (`linked_user_id IS NULL` guard, first-come)
      on an existing unclaimed Author's page; `GET /users/{user_id}/works` (mirrors
      `public_library`, gated on `profile_visible`) + "Works by [name]" section on the
      profile screen; `AuthorOut`/`GET /catalog/authors?q=` returns `linked_user_id` so
      the add-book author typeahead and global search's new "Authors" section can both
      show a 🔗 "on Kitabi" pill on a linked friend; author page gets a "View their
      Kitabi profile" row when linked. Mockups: `kitabi_screens.html` 4e/4f/4g/7c.
      **Simplified 14 Jul 2026** (owner: invited friend circle, not open
      sign-up) — no claim/evidence/approval workflow, no verified badge; the heavier
      version is shelved in `docs/author-identity-and-moderation-plan.md` for if this ever
      opens beyond invited friends.
      **Revised 22 Jul 2026** — the first-come rule is gone. "This is me" was hidden
      (2fccf1f) as an unverifiable edit to shared catalog data, and is now back behind an
      approval queue: both paths (create-time checkbox and the existing-author button) file
      a pending `author_claims` row (migration `000029`, RLS) instead of writing
      `authors.linked_user_id`. The claimant sees a "Pending review" notice via a
      per-request `claim_pending` flag; every other reader keeps seeing the old value.
      Only `catalog_service.approve_claim` writes the link
- [ ] Author claim review UI — approval is **manual** today: no endpoint, no admin screen.
      `catalog_service.approve_claim` / `reject_claim` are the whole decision path (tested),
      so this is a router + screen over existing logic. Until then, approve from `psql`:
      look up the pending row in `author_claims`, then call the service (or set
      `authors.linked_user_id` and the claim's `status`/`decided_at` in one transaction)
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
- [x] Reading sessions — timed logs (10 Jul 2026, pulled forward from the v1.5 parking lot,
      owner request): a new syncable `reading_sessions` table (migration `000023` API-side,
      schema v4 Drift-side) — `library_entry_id`, `started_at`, `ended_at`, `duration_seconds`,
      optional `page_start`/`page_end`, wired into the generic sync push/pull registry exactly
      like ratings/reviews. The live "timer running" state itself stays device-local
      (`ActiveSessionController`, KeyValues-backed so it survives an app restart mid-session) —
      only ever becomes a synced row once stopped. Only one session runs app-wide at a time;
      starting a new one auto-stops and logs whatever was running first. Book page gets a
      "Reading Session" card (Start button + recent-sessions log) that opens a full-screen
      pocket-watch view (a real sweeping hand via `AnimationController`, an "in the zone" badge
      past 20 minutes); stopping shows a wax-seal confirmation (session minutes, this-week
      total, an optional page-number field) before returning to the book page. A slim mini-bar
      (`ShellScaffold`) follows a running session across every tab — its own quick-stop control
      skips the wax-seal ceremony on purpose, reserved for stopping from the watch face itself.
      Verified with dedicated unit tests (`ActiveSessionController` start/stop/auto-switch/
      restart-hydration, `computeReadingTimeStats` bucketing) plus a full widget-test flow
      (start → watch face → stop → wax seal → back on the book page with the session logged)
- [x] Home screen reworked — "The Stat Wall" (10 Jul 2026, owner feedback: the previous
      bordered-card dashboard read as "costume, not design" and "not modern enough"): the
      reading-goal slip became an oversized editorial hero number on a gold wash; the four
      shelf-count cards flattened from a bordered 2×2 grid into one typographic row (big serif
      numbers, no boxes); the fresh-covers strip dropped its skeuomorphic gold shelf-line/shadow;
      currently-reading cards went dark (mini-player styling, matching the reading-timer's own
      language) and now show a live gold dot when their session is the one actively running —
      same visual system the persistent mini-bar uses. Same paper/ink/oxblood/gold tokens
      throughout; all pre-existing functionality (tap-throughs, progress editing, multi-book
      support) carried over unchanged
- [x] Insights gains a reading-time section (10 Jul 2026): a gradient area chart of the current
      week's minutes per day (`CustomPainter`, matching the existing pages-per-month line
      chart's technique), this week's total against last week's delta, and one plain-language
      observation derived from session timestamps ("You read most on Wednesdays, often around
      9–10 PM") — only shown once there are enough sessions (5+) to say something real

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
- [x] Borrowed books unified into the main library (15 Jul 2026, owner request):
      a borrowed book is now a real `library_entries` row (`ownership: 'borrowed'`)
      instead of living only in the lending ledger, so it reads/tracks status and
      progress exactly like an owned book, and — the actual problem being
      solved — **staying returned doesn't remove it from the library**; the
      library grid keeps showing it with a grey "Returned" tag, "returned" is
      derived from the linked `LendingRecord.returned_date` (never stored twice).
      "Log a borrowed book" and the cross-user lend mirror both create/reuse this
      entry (one active entry per edition — re-borrowing the same book reuses it,
      doesn't fork a duplicate). Buying a borrowed book flips the same row's
      `ownership` to `'owned'` in place (same id — reading status/progress/notes
      carry over untouched) via a "Make this mine" action on the book page,
      confirmed with a dialog explaining the lending history stays as a log.
      The separate library-grid "Borrowed" section is gone — one grid, banded.
      API: `library_entries.ownership` column + migration (backfills existing
      unlinked borrowed `lending_records` into entries); Flutter: Drift schema
      bump to v5 + migration.

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
- [x] **Time to finish** (Area 13, P1–P9) — the reader's own pace, from sittings that
      recorded a page range, turned into hours / sittings / weeks. Pure
      `computeReadingPace` + `estimateFinish` (`features/insights/reading_pace.dart`,
      16 unit tests) behind a reactive `readingPaceProvider`; one `TimeToFinish` widget
      covers every state — total, remaining + finish date, the book's own pace, the
      finished book's *actual* with a calibration line, the assumed-pace state, and the
      no-page-count prompt. Rides inside `_ReadingCard` on an owned book and as a gold
      strip on the frontispiece of one you don't own. Library gains a **time-to-finish
      facet** (buckets, cover time tags, and an honest "N can't be estimated" count).
      Deliberately **not** a crowd average — see the note in docs/screen-design.md;
      the shared figure stays locked until enough readers have logged pages
- [x] **The sitting on the lock screen** — one `ReadingLiveActivity` API, two
      mechanisms, because the platforms genuinely differ. **iOS:** a real Live
      Activity — new `ReadingActivity` widget extension (ActivityKit + WidgetKit,
      iOS 16.2+, added to `Runner.xcodeproj` by script), lock-screen card and Dynamic
      Island in the Reading Room palette, driven from `ReadingActivityController.swift`
      over a method channel. **Android:** an ongoing notification the system ticks
      itself (`usesChronometer` from the sitting's start), which is Android's
      equivalent below Android 16. Started in `ActiveSessionController.start`, ended in
      `stopAndLogActiveSession` (the one stop path), and reconciled on every resume so
      a background-isolate stop can't leave a clock running on the lock screen.
      Follow-up: Android 16 promoted "Live Updates" (`Notification.ProgressStyle`)
      once the notifications plugin exposes it
- [x] **Tapping the live surface opens that book's timer** — iOS via a
      `widgetURL` on the Live Activity (`in.kitabi.kitabi://reading-timer/:id`,
      its own host so the Supabase OAuth callback on the same scheme is
      untouched); Android already carried the entry id as a notification
      payload. Fixed the duplicate-route bug this exposed: `navigateFromExternal`
      now refuses to push the route already on top
- [x] **"I finished the book" on the stop faces** — the timer's wax-seal face and
      the shared quick-stop sheet both offer it, in moss and secondary to the
      ordinary way out, so stopping is never blocked. Marks the book Read,
      stamps the finish date, and settles the last page — all through one
      `markBookFinished`, which the book page's status row now uses too

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

## Phase 9 — In-app promotions

Design: [promotions-plan.md](promotions-plan.md) · mockups:
[promotions-mockup.html](promotions-mockup.html). First-party only — no ad SDK,
no advertising identifier, no new bill (CLAUDE.md rule 8).

- [x] Migration `000034`: `promotions` / `promotion_contents` / `promotion_events`,
      RLS deny-by-default, plus `profiles.promotions_opt_out`. `status` stores the
      operator's *intent* (draft/published/paused) and live/scheduled/ended are
      derived from the dates — nothing runs on a timer, so there is no day the
      timer didn't run and a finished campaign is still live
- [x] `promotion_service`: the targeting resolver (languages, platform, app version,
      account age, library size, reading status, genres, reader ids, rollout %,
      exclusions — unknown facts fail *closed*), language-variant selection,
      frequency/dismissal rules, and the audience estimate. The estimate reuses the
      same `matches()` the serve path uses, so it can't drift from what ships
- [x] `GET /promotions` (server-resolved, ETag→304) + `POST /promotions/events`
      (batched, idempotent on device-generated ids, always 200); `X-Platform` header
      on the app's Dio interceptor. 41 tests — every targeting rule for the match
      *and* the non-match, since both directions fail silently in production
- [x] Admin console **Campaigns** (editor+): list grouped by derived state with the
      dismissal rate in oxblood past 20%, four-tab composer with a live phone preview,
      audience builder with a live estimate + narrowing bars, schedule/frequency,
      per-variant results, one-tap Stop now, audit row on every mutation
- [x] App: `CachedPromotions` + `PromotionEventQueue` (schema v8), repository,
      `StreamProvider`, `PromoBanner` / `PromoCard`, Home wiring, l10n, the reader's
      opt-out switch in Profile, cache cleared on sign-out
- [x] Verified on an Android emulator via `lib/main_uidemo.dart`: both surfaces render,
      dismiss is instant and database-backed, undo works. Fixed one real bug found only
      there — Material's default pink snackbar action on the constant-dark slab, now
      themed gold app-wide
- [ ] Decide: sponsored placements at launch, or Kitabi's own promos only (the
      `sponsor` field ships either way; it drives the disclosure label)
- [ ] Image hosting — an R2 `promo-assets` bucket (same Cloudflare account as the
      nightly backups, so no new service and no new bill) with upload from the console.
      Until then `image_url` is a pasted URL, and a card whose image fails renders as
      the text shape
- [ ] Privacy-policy paragraph: that Kitabi shows its own promotions, chosen
      server-side from language and library, and counts engagement. Ships with the
      feature, not after it
- [ ] End-to-end on a real phone against the deployed API — create a campaign in the
      console targeted at your own reader id, publish, confirm it appears, dismiss it

## Phase S — API hardening

Plan: [web-platform-plan.md](web-platform-plan.md) §11. Ranked by what abuse
actually costs, not by how discoverable an endpoint is — **you cannot stop a
non-browser client from calling a public API**, so the controls are rate and
cost, never secrecy.

- [x] **Daily spend limits on the two paid endpoints** (4 Aug 2026) — migration
      `000037` + `services/llm_quota.py`. Per-reader daily quota *and* a global daily
      circuit breaker, in Postgres (rule 8, no Redis). The per-reader counter is an
      atomic `INSERT … ON CONFLICT DO UPDATE … RETURNING`; the global check is
      deliberately check-then-act. Consumed before the call, **not refunded** on
      failure. 429 `quota_exceeded` / 503 `llm_unavailable`, both with `Retry-After`.
      The recs meter sits in the service next to `_generate_picks`, not the router,
      so cold-start readers don't burn quota on a call that never happens
- [x] **`GET /catalog/isbn/{isbn}` requires auth** (4 Aug 2026) — the one public read
      that spent *OpenLibrary's* quota and wrote to our catalog. No app change needed
- [~] **Cloudflare rate-limiting rule — written, not applied** (4 Aug 2026).
      `infra/cloudflare/rate_limits.py` (+ README) defines it as code and applies it
      idempotently; dry-run by default. **Blocked on a token:** the Actions
      `CLOUDFLARE_API_TOKEN` is scoped to *Pages: Edit* and has no zone/WAF permission,
      and must not be widened — that would let the landing-page deploy rewrite the
      firewall. Mint a separate Zone→WAF→Edit token scoped to kitabi.in, then
      `./rate_limits.py --apply`.
      Free plan allows **one** rate limiting rule, IP-only, short window — so it is a
      **burst shield, not an anti-scraping control**, and it's spent on *availability*
      (a single IP saturating the 10+10 DB pool), because spend is already bounded by
      `llm_quota` and scraping is low-harm by design. Action is `block`, never a
      challenge — the app and the edge functions can't solve one. Verified bots exempt,
      or crawling breaks and the whole SEO plan with it
- [ ] **Exempt the edge from the rate limit before W1 ships.** Once pages are
      edge-rendered, most API traffic stops being "one IP per reader" and becomes
      "Cloudflare", so a per-IP ceiling can throttle the edge itself and take the public
      site down under exactly the spike it should survive. Needs the edge→origin shared
      secret plus a `skip` custom rule ordered ahead of the limiter
- [x] **CORS scoped to what the share pages actually do** (4 Aug 2026) — was
      `allow_methods=["*"]` + `allow_credentials=True` + `Authorization` allowed, i.e.
      every method advertised to every browser and cookie-bearing cross-origin reads
      permitted. Now `["GET"]`, credentials off, `Accept` only. The mobile app isn't a
      browser and the admin console is a separate same-origin app, so neither is
      affected. 7 tests in `test_cors.py`; the block disappears entirely at W1, when
      the browser stops calling the API
- [ ] `Cache-Control` on the public catalog GETs so Cloudflare serves repeat reads and
      the API stops being touched for them
- [ ] Surface 429/503 from the paid endpoints in the app as a calm message rather than
      a generic error state (recs screen + the add form's "Fill in from photos")
- [ ] Alert on anomalous volume — a daily job that flags a reader at their cap, or the
      global breaker tripping, so the first sign isn't the invoice
- [ ] Edge→origin shared secret on `/public/*` (blocked on W1 — meaningless until the
      browser stops calling the API directly)
- [x] **Unblock the AI crawlers** (4 Aug 2026) — Cloudflare's "Managed robots.txt" setting
      prepended a block disallowing GPTBot, ClaudeBot, CCBot, Google-Extended, Bytespider,
      meta-externalagent, Amazonbot and Applebot-Extended, plus `Content-Signal: ai-train=no`.
      It could not be overridden from our own file (a named `User-agent` group beats `*`).
      Turned off in **AI Crawl Control → Overview**; verified in the served response — no
      managed block, no `Disallow`, no `Content-Signal`. A reference site whose value is
      content nobody else has *wants* to be citable by answer engines
- [x] **`robots.txt` + `noindex` on `admin.kitabi.in` and `api.kitabi.in`** (4 Aug 2026) —
      both hosts served no robots.txt at all (a 404) and the admin sign-in page carried no
      `noindex`, so the console was crawlable and indexable. Found while checking AI Crawl
      Control, which showed `admin.kitabi.in/graphql/console` as the single most-crawled
      path in the zone — a scanner probing for a GraphQL console that doesn't exist (it
      404s correctly; nothing was exposed). Now `Disallow: /` plus
      `X-Robots-Tag: noindex, nofollow, noarchive` on **every** response of both hosts,
      including 404s, redirects and static assets — an unconditional middleware, not a path
      allowlist, because an allowlist rots as routes are added. Two layers because they do
      different jobs: robots.txt asks crawlers not to *fetch*, the header stops *indexing*
      on any fetch that happens anyway — and a blanket `Disallow` alone actually makes that
      worse, since a crawler forbidden to fetch the page can never read a `noindex` inside
      its HTML. `/.well-known/` is carved out on the API (defensively — nothing is served
      there today) so a future app-association file or ACME challenge can't be broken
      silently. **The hazard here was deindexing kitabi.in itself**, so that is the thing
      the tests actually guard: `test_edge_never_forwards_origin_headers` parses the real
      edge sources to prove the sitemap proxy and cover proxy build fresh headers rather
      than passing the origin's through, and `test_no_public_page_emits_an_api_host_url`
      proves nothing public points at the now-disallowed host. Both were verified by
      sabotaging the code and watching them fail. Neither layer is access control — the
      real controls stay the session cookie, TOTP and Cloudflare
- [x] `slug` column (unique, indexed) on `works` / `authors` / `publishers` / `series`,
      generated from `title` or **`title_translit`** when the title is non-Latin;
      disambiguate by author → year → `-N`. Migration + backfill + generation on create
- [x] `/public/*` read layer — page-shaped payloads (`book`, `author`, `publisher`,
      `series`, `genre`, `language`, `home`), keyed by slug. **One API call per page**;
      thin projections over the existing services, additive to the app's endpoints
- [x] Public reviews — `GET /catalog/works/{id}/reviews` currently requires `CurrentUser`;
      the visibility flags and anonymization already do the right thing, the auth gate
      is simply the wrong gate for a public page
- [x] Totals on browse (as a `total` field on the page payload) — `GET /catalog/browse/works` (no totals today → no "1–40 of 312",
      no finite pagination for crawlers)
- [x] **Self-hosted fonts** (4 Aug 2026) — Fraunces + Inter variable woff2 in
      `landing-page/fonts/`, latin + latin-ext behind `unicode-range`, `font-display:swap`,
      the two latin faces preloaded, cached immutable for a year. Verified live:
      `font/woff2`, zero references to fonts.googleapis/gstatic on any page.
      **Indic families deliberately NOT bundled** — 14 languages would be ~500 KB and
      every current platform ships Indic system fonts (native titles render correctly on
      the deployed hubs). Reasoning in `landing-page/fonts/README.md`
- [x] **Cover proxy** (4 Aug 2026) — `/img/c?u=…`, fetch once, year-long immutable edge
      cache, served from our origin. **The allowlist is the security model**: only
      covers.openlibrary.org and our Supabase bucket, https only, no credentials, no
      non-standard ports, response content-type must be an image, refusals before any
      fetch. Probed against the real runtime — every disallowed host returns 400,
      including the suffix attack. A cover from an unexpected host passes through
      unproxied rather than breaking
- [x] **Cover backfill into the Supabase `covers` bucket** (4 Aug 2026) —
      `jobs/backfill_covers.py` + `services/cover_storage.py`. A cache is not ownership:
      the edge proxy means no reader waits on OpenLibrary, but if the image is removed
      the cover is gone. 770 of 772 catalogue covers are hotlinked; the job trickles them
      into the bucket we already own (25 per run, every 10 min, ~0.4s between fetches —
      OpenLibrary is a free non-profit service and a burst is both abusive and
      self-defeating). Idempotent, deterministic path per edition id, upserts.
      **Needs `SUPABASE_SERVICE_ROLE_KEY` on Railway** — dormant and silent without it,
      same gate as recs and push (rule 8)
- [ ] `POST /internal/purge` → Cloudflare cache purge by URL, fired on catalog writes

### W1 — Server-render the three pages that already exist

- [x] `landing-page/functions/_lib/` — shared layout/components/cache/JSON-LD renderer
      (plain tagged template literals; the existing `_og.js` `Book` builder gets lifted,
      not rewritten)
- [x] `/book/<slug>`, `/author/<slug>`, `/publisher/<slug>` fully server-rendered
- [x] Edge cache: `s-maxage=300`, `stale-while-revalidate=86400`
- [x] **AASA gains `/book/*`, `/author/*`, `/publisher/*` — shipped
      BEFORE the redirect.** iOS re-evaluates the association only at install, so
      removing or racing the old paths orphans every installed app. Expect Apple's CDN
      to lag ~24 h
- [x] `/b/:uuid`, `/a/:uuid`, `/p/:uuid` → **301** to the slug URL (never removed —
      they're in Google's index, in every share card, and bound to the app links)
- [x] Done: a JS-disabled browser sees the whole book page, TTFB < 100 ms warm

### W2 — The front door

- [x] `/` — search box, featured book, recently added, highest rated, the language grid
      (the row that gives every hub a link from the root), translation pairs, one app band
- [x] `/search?q=` — server-rendered, grouped, `noindex, follow`; works with JS disabled;
      shows the cross-script match line ("matched your spelling 'chemmeen'")
- [x] `/browse?…` — faceted, `noindex, follow`, still fully linked
- [x] `/public/home` feeds: recently added, highest rated, trending (library adds in 30
      days, computed in Postgres, cached 1 h — no Redis)

### W3 — Hubs

- [x] `/genre/<slug>`, `/language/<slug>`, `/language/<slug>/<form>` (series/translations still open)
- [x] `/series/<slug>` and `/translations/<slug>` routes, `/series/<slug>`,
      `/translations/<slug>` — one hub template
- [ ] Editorial intros, 150–250 words each, hand-written per hub. **This is the whole
      difference between a hub and a thin auto-generated list**
- [x] `/list/<slug>` + `/lists` — **ten editorial lists written** (the launch target),
      55/55 slugs verified present. They live in
      `landing-page/functions/_lib/lists.js` as content, not data.
      **Run `landing-page/tests/check_lists.py` after editing one** — it resolves every
      slug against the live API and fails if a list would 404. The first draft was
      curated against the canon rather than the catalogue and every entry was silently
      skipped, which is why that check exists
- [ ] Done when: every indexable page is ≤3 clicks from home

### W4 — Indexation

**Pre-submission audit (4 Aug 2026)** — run before handing the site to Search
Console, on the principle that submitting a site with known defects just means
finding out about them slowly, from Google, weeks later. Three findings, all
fixed:

- [x] **www.kitabi.in was a complete duplicate host** — serving the entire site
      byte-identical to the apex at HTTP 200 with `index, follow`, its own
      robots.txt and all. Canonical tags already pointed at the apex so Google
      would probably have consolidated it, but that is not a thing to leave to
      probability at submission time. Now 301s to the apex from a Pages
      `_middleware.js` (a route file cannot do it — named routes never reach the
      `[[path]]` catch-all), with `/.well-known/` excluded because Apple does not
      follow redirects for the app-association file
- [x] **The static sitemap listed redirects** — `/privacy.html` and `/terms.html`
      both 308 to the extensionless form, so every crawl would have reported
      "Page with redirect" for the two pages the app stores require
- [x] **No hub or directory was in any sitemap** — `/lists`, `/languages`,
      `/translations`, `/authors`, `/publishers` and the fourteen language hubs
      are all `index, follow` and appeared nowhere. 3 URLs → 22
- [ ] **Submit to Search Console + Bing Webmaster** — needs the owner's Google
      account; cannot be done from here. Domain property (DNS TXT in Cloudflare)
      is the right shape: one property covering apex, www, http and https

Two things the audit deliberately did **not** treat as bugs: `/browse` and
`/search` are `noindex, follow` by design (faceted browse explodes
combinatorially), and a 404 page emitting `canonical` → the homepage is
harmless, since it is `noindex` and carries a 404 status. The genre hubs stay
out of the sitemap until a work actually carries a genre.

- [x] The content floor: a work is `index, follow` only with a cover **or** a description
      ≥120 chars **or** ≥1 review **or** ≥2 editions **or** ≥1 rating, and a title that
      isn't transliteration noise. Everything else `noindex, follow`. Same idea for
      authors (bio or ≥2 works) and publishers (≥3 editions)
- [x] `sitemap_service.build_page` emits **only indexable rows**, at canonical slug URLs — it emits every
      non-deleted row today, which is exactly the signal we don't want to send
- [ ] Extend sitemaps to series / genres / languages / lists / translation groups,
      with `<image:image>` for covers
- [x] JSON-LD per page type; `AggregateRating` **only when a real rating exists** — never
      zeroed, never invented
- [x] Pagination: unique title + self-canonical per page; never canonical page 2 → page 1
- [ ] `hreflang` scaffolding for a future `/ml/`, so it isn't a retrofit
- [ ] Search Console + Bing Webmaster verified; Lighthouse CI failing the build on
      LCP > 1.2 s or a document-size regression

### W5 — Catalogue depth (parallel, and never really finished)

- [ ] **Merge duplicate authors** — `Basheer, Vaikom Muhammad` and `Vokom M. Basheer` are
      live right now as two rows for one person. Two rows = two thin pages competing.
      **Prerequisite for indexing author pages at all**
- [ ] Fix imported titles — ~30% carry OpenLibrary transliteration noise
- [ ] **Attach genres** — `browse/genres` returns `[]`. Classify the seed set against a
      ~40-genre closed vocabulary, LLM-assisted with human review (the Anthropic client
      already exists in the API). Nothing genre-shaped can ship before this.
      **Raised stakes (9 Aug 2026):** the browse filter UI now exists on web + app
      (genre/type/length chips, rating + just-added sorts — docs/discovery-trends.md),
      so this and form/page-count enrichment are what stand between those filters and
      being useful — 1 genre-tagged work of 1,405 today; the empty chip rows hide
      themselves until the data lands
- [ ] Cover coverage — typeset covers where none exists, so no page has a hole
- [ ] Descriptions for the top 300 works, 120–200 words. Highest-leverage manual task on
      the list: it flips 300 works past the content floor and gives each a real meta description
- [x] `/reader/<username>` public profiles (both visibility flags honoured; a private profile has no page at all)
- [x] A reader's own public reviews, on their profile — web *and* app (9 Aug 2026).
      `review_service.reader_reviews` behind `GET /users/{id}/reviews` (app) and
      `ReaderPage.reviews` (web). Gated on `profile_visible` + each review's own
      `visible`, deliberately **not** on `library_visible`: a review is published on
      its own flag and a private shelf doesn't retract it. Reviews now also lift a
      profile past the content floor on their own — original prose is the reason the
      page is worth crawling

- [ ] **Unblock AI crawlers in the Cloudflare dashboard** (owner action — needs
      zone access, which no token here has). Cloudflare prepends a managed block to
      robots.txt disallowing GPTBot, ClaudeBot, CCBot, Google-Extended, Bytespider,
      meta-externalagent, Amazonbot and Applebot-Extended, plus
      `Content-Signal: ai-train=no`. It is **advisory, not enforced** — those user
      agents still get a full 200 — but well-behaved crawlers obey it, so ChatGPT,
      Claude and Perplexity will not surface Kitabi. It cannot be overridden from
      `landing-page/robots.txt`: a specific User-agent group beats `*`. Worth
      distinguishing crawlers that TRAIN (GPTBot, CCBot, Google-Extended) from those
      that FETCH to answer with attribution (OAI-SearchBot, PerplexityBot, ClaudeBot)
      — allowing the second while restricting the first is a coherent position

### W6 — `[LATER]`

- [ ] `/ml/` Malayalam UI + `hreflang`

### Open decisions (owner)

- [ ] Slug column vs. hash-suffixed UUID — recommendation is the column (one migration,
      clean URLs permanently; a hash prefix fails *silently* as two books on one URL)
- [ ] Content-floor thresholds — the proposal indexes ~250–400 of 1,402 works at launch
- [ ] Who owns the ~40-genre vocabulary, and is LLM-assisted classification with human
      review acceptable for the seed set?
- [ ] Editorial writing capacity — the descriptions and hub intros are ~40 hours of writing
- [x] `buy_links` (`[WIRED]`, empty): affiliate programmes are revenue but also a
      disclosure obligation. In or out for v1? — **In (8 Aug 2026):** links are
      *generated* at read time from the ISBN (`api/app/services/buy_links.py` —
      Amazon.in `/dp/<ISBN-10>` + Flipkart search; docs/revenue-plan.md §3.1),
      merged after any stored links on every work payload, so web + app render
      them with no client work. Tags come from `AMAZON_ASSOCIATE_TAG` /
      `FLIPKART_AFFILIATE_ID` (unset = untagged links, no disclosure); affiliate
      links carry `rel="sponsored"` and a disclosure line on both surfaces.
      Owner action outstanding: sign up Amazon Associates India, set the tag in
      Railway

## Phase A — The author page as a reference page

Plan: [author-page-plan.md](author-page-plan.md) · Mockups: [author-mockups.html](author-mockups.html).

> **Deferred — this is a future plan, not current work (owner decision, 4 Aug 2026).**
> Designed in full so it can be picked up cold. Don't start A0 without saying so.
> Nothing here decays: Wikidata isn't going anywhere, and the P648 match rate only
> improves as the catalogue grows. **What comes first is W5** — genre classification
> (still 0 works with a genre) and descriptions, which is what actually makes any of
> these pages rank — plus Search Console submission and the edge→origin secret.

Depends on W being live (it is). The live page already renders the four blocks we
can compute — works, publishers, decade bar, stats. This phase adds the ones that
need a *source*.

**Two rules that are not negotiable, and everything below is shaped by them:**
an LLM never sources a biographical fact about a real person (§2.2), and every
fact is stored with its provenance so the page can say "sources disagree" and can
say nothing at all (§2.3). Where we know nothing, the block disappears — no
"Unknown", no empty rows.

### A0 — Schema

- [ ] `authors` + `birth_date`, `death_date`, `birth_place`, `description`,
      `native_name`, `wikidata_id`, `fact_source`, `facts_synced_at`
- [ ] **Date precision** (`year` | `month` | `day`) alongside every date — Wikidata gives
      `1912-04-17` for one author and `1914` for another, and rendering the second as
      "1 January 1914" invents a day
- [ ] `author_awards` (name, year, awarding_body, source, source_url)
- [ ] `author_identifiers` (scheme, value) — wikidata | viaf | openlibrary | isni
- [ ] `author_facts` (field, value, source, source_url, confidence) — the table that makes
      "born 1912, some sources say 1914" representable rather than a silently picked winner
- [ ] RLS enabled, zero policies, on all three new tables (rule 11)

### A1 — Enrichment job

- [ ] `jobs/enrich_authors.py` — same trickle shape as the slug and cover backfills
- [ ] Match on **P648 (OpenLibrary id)**, which 1,159 of 1,162 authors carry. Name search
      only as a fallback, and only on a single unambiguous hit; **two candidates → skip and
      queue for review**, never guess. A wrong match here attaches one person's death date
      to another
- [ ] Pull labels (native-script names), dates, birthplace, occupations, awards,
      identifiers, Commons portrait
- [ ] Never overwrite a verified-author or reviewed-contribution value (the trust ladder, §2.4)
- [ ] Record `fact_source` + `facts_synced_at` on every write
- [ ] Store the Commons credit line **at import time** — it cannot be reconstructed later

### A2 — The page

- [ ] Infobox, awards timeline, sources block, "improve this page"
- [ ] Empty blocks disappear entirely; disagreeing sources render as "born 1912 (some
      sources say 1914)"
- [ ] `Person` JSON-LD grows `birthDate`, `deathDate`, `birthPlace`, `award`,
      `knowsLanguage`, `jobTitle`, `image`, and **`sameAs`** → Wikipedia, Wikidata, VIAF,
      OpenLibrary. `sameAs` is how a search engine reconciles our page with the entity it
      already knows, which is what lets a small site surface for a well-documented person
- [ ] Content floor for authors gets stricter *and* more useful: indexable on a bio **or**
      a birth date **or** an award **or** ≥2 works
- [ ] Mobile: infobox **before** the prose (M6) — the question that brought the reader is
      almost always a fact, not a paragraph

### A3–A6

- [ ] A3 — Wikipedia lead paragraphs, **attributed inline** (CC BY-SA; the credit is a
      licence obligation, not a design flourish, and survives the mobile squeeze)
- [ ] A4 — contribution loop, reusing the `work_revisions` approve/reject pattern
- [ ] A5 — verified authors edit their own page (`author_claims` exists and is unused;
      Wikipedia structurally cannot let subjects do this, so it is a real differentiator)
- [ ] A6 — the same treatment for publishers, then series

### Open questions

- [ ] Which Wikipedia language edition leads for a Malayalam author — `en` (more readers)
      or `ml` (better coverage of the subject)? Probably `ml` with an `en` fallback
- [ ] Do we re-sync facts, and how often? A writer dies and the page says otherwise
      (`facts_synced_at` exists for this, but nothing consumes it yet)
- [ ] Commons portraits carry per-file licences, a few of which are non-commercial.
      Filter at import, or store the licence and decide at render?

## Parking lot — v1.5 (designed or deliberately deferred)

- [ ] Quote capture with OCR (regional scripts) — S14 designed
- [ ] Embedding similarity ("books like this")
- [ ] Semantic / mood search
- [ ] Shelf-scan-to-library (camera reads spines)
- [ ] Reading sessions (timed logs)
- [ ] Reading challenges; spoiler-aware companion; AI book insights
- [ ] Web *app* — the signed-in Flutter experience in a browser. Distinct from Phase W,
      which is the public read-only reference site and needs no accounts
- [ ] Email/mobile OTP; community layer (flip the `[WIRED]` switches)
