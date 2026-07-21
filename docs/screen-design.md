# Kitabi screen design — "The Reading Room"

[kitabi_screens.html](kitabi_screens.html) is the **design source of truth** for the
Flutter app. Open it in a browser; every v1 screen is mocked there as a phone frame.
This file documents the tokens and patterns so `app/lib/core/theme` can mirror them.

## Voice

Quiet, literary, unhurried — a private library, not a feed. Paper and ink, not glass
and glow. Flourishes are typographic (serifs, small caps, a fleuron ❦, rotating
literary quotes), never animated gimmicks.

## Color tokens

| Token | Hex | Use |
|---|---|---|
| `paper` | `#F6F0E3` | App background (aged paper) |
| `paper-deep` | `#EFE6D2` | Wells, inset headers, chart track |
| `card` | `#FFFCF4` | Raised cards (fresh page) |
| `ink` | `#2B2118` | Primary text |
| `ink-soft` | `#7A6A55` | Secondary text |
| `line` | `#E2D6BD` | Hairline rules & borders |
| `oxblood` | `#7E2A33` | Primary actions, FAB, "Reading" status |
| `oxblood-deep` | `#5E1F26` | Pressed state |
| `gold` | `#B8862B` | Stars, favourites, lending accents |
| `gold-soft` | `#F0E2C2` | Gold fills / chart bars |
| `moss` | `#48663F` | "Read", success, returned stamp |
| `slate` | `#43617E` | "Wishlist", informational |
| `stamp-grey` | `#9A8F7C` | "Stopped", disabled |
| dark panel | `#3A2C1E` | The single dark accent card (AI pick, quote card) |

Dark-of-night exceptions: the ISBN scanner screen is dark (`#1E1710`) because it is a
camera; everything else stays paper.

## Type

- **Display / titles:** Fraunces (serif, 400–600). Screen titles ~19px equivalent.
- **UI / body:** Inter (400–700).
- **Quotes & review text:** Fraunces italic ("literary voice").
- Section labels: 9px-equivalent, uppercase, letter-spaced, `ink-soft`.

## Signature patterns

- **Status pills** — solid soft-tinted pills, uppercase, small: Reading (oxblood on
  `#F2DEDA`), Read (moss on `#E3EAD9`), To read (`#8F681E` on `#F2E6C4`), Wishlist
  (slate on `#DEE7EF`), Stopped (grey on `#EAE4D6`). No outlines or dashed borders
  anywhere — tints carry the meaning.
- **Covers first, one frame for all** — every cover sits in the same frame: rounded
  corners, left spine shade, drop shadow. No image → a generated cover typeset from
  title + author on a colour derived from the book. Uploaded photo or catalog image →
  fills the same frame edge-to-edge. Overlays (gold ribbon = favourite, gold
  "WITH <NAME>" band on lent books) render identically over both, so mixed shelves
  still read as one bookshelf. See the "Cover treatments" exhibit in the mockups.
- **Progress in pages** — "p. 302 of 724 · 42%", never a bare percentage.
- **Ticker titles** — when a title or author overflows a *generated* cover, it scrolls
  gently (music-player style: pause → slide → settle back) instead of truncating.
  Rules: overflow-only, never in loops on a full grid (grids scroll on long-press or
  once on first render; single-book cards may auto-run one at a time), disabled under
  reduced motion. Uploaded cover images never get tickers — the art carries the title.
  Implementation note: nowrap ticker text must not widen layout — grid tracks need
  `minmax(0, 1fr)` (see the library grid in the mockups).
- **Three-way split made visible** on the book page: rating (shared), review (visibility
  control, private by default), notes on dashed "slip paper" (always private).
- **AI stays quiet** — recommendations are cards with a "WHY THIS?" reasoning block
  quoting the user's own ratings; opt-in, with a visible off switch. One labelled
  pick on Home, never a feed.
- **Bottom nav** — Home · Library · [+] · Lending · Insights; oxblood FAB opens
  add-book (scan-first). **A footer tap always lands fresh** (owner request,
  19 Jul 2026): `goBranch(initialLocation: true)` pops nested routes, and a
  per-tab reset tick (`libraryTabResetProvider` / `lendingTabResetProvider`,
  bumped on tap) resets the in-screen state too — Library snaps back to the
  "All books" grid (closing any opened shelf, clearing filters, scrolling up,
  forced over the saved Shelves preference), and Lending re-keys to its first
  tab. So tapping a tab never drops you onto the last sub-view you left.
- **Swipe from the left edge to go back, on every page and platform** (owner
  request, 19 Jul 2026). `buildAppTheme` sets a `PageTransitionsTheme` that uses
  `CupertinoPageTransitionsBuilder` for *all* platforms, so every pushed route
  gets the same draggable back gesture — Android's default (Zoom) had no
  edge-swipe at all. The one custom overlay route (the full-screen cover viewer)
  keeps its own front/back swipe and is dismissed by tap/back.
- **Lending is two tabs, one ledger** — "Lent out" and "Borrowed" sit on the same
  segmented control at the top of the Lending screen; it's one record set seen from
  either side, not two features.
- **Linked vs. self-logged borrowing** — a borrowed-book row gets a small gold
  "🔗 on Kitabi" badge when the lender is also a registered user and named you (the
  loan appeared with no action on your part); no badge means you typed it in yourself.
  Both are plain personal records — no notifications or social layer yet, just the
  optional user-reference on the existing lending record.
- **Two share cards, one family** — the per-book card (any book, any time: cover,
  rating, blurb) and the personal-endorsement card (your rating + your review line,
  reached from a book you've actually read) share the same gold-framed layout and
  destinations row; a toggle on the per-book card folds your rating/note in when you
  have them, so it's one mental model, not two features.
- **Counterparty names are doors too** (added 7 Jul 2026) — any borrower/lender
  name on a loan (ledger cards, book page lending history) is tinted oxblood and
  tappable, opening the loans-with-that-person page. Linked Kitabi users match by
  user id; self-logged free-text names match by name — both get a page. The book
  page's lending card carries the full per-book history (every loan both ways,
  newest first, with dates, notes, and Returned/Out-now stamps), including on a
  book you only borrowed.
- **A borrowed book lives on the library grid, not just the Lending screen**
  (added 15 Jul 2026) — S5's `ShelfCover` gets a grey "Returned" tag (independent
  of the lend/borrow bands, and doesn't hide the status pill) once a borrow closes;
  the book stays on the shelf rather than disappearing, so returning a book never
  reads as losing your reading history. The book page's lending card gets a
  matching header for a borrowed copy — "Borrowed from X" / "Mark returned" while
  open, "Returned" / "Make this mine" once closed — the latter a confirm dialog
  that flips the same entry to owned in place (id unchanged) and says plainly that
  the lending history stays below as a log.
- **Add form is capture-first, essentials-next, details-on-demand** (rebuilt
  16 Jul 2026) — scan/photo tiles lead full-width; cover, title, author,
  language, Type, and Genre are the whole visible form; Type (`Work.form`,
  closed vocabulary, single-select) and Genre (multi-select) are one-tap chip
  rows with every option visible because they power the library filter;
  series/publisher/ISBN/pages/format/description fold into a "More details"
  disclosure (auto-open on edit or after a prefill, announced by a gold
  provenance banner); Save is a sticky bottom bar with the shared-catalog
  consequence spelled out under it.
- **Author/publisher names are doors, not just labels** — anywhere a name appears
  (search results, book page, add/edit form), it's tinted oxblood and tappable,
  opening a browse page for everything by that author or publisher. One list
  pattern serves both: chips split owned vs. not (author page) or lean on genre
  (publisher page, since one publisher spans many authors); unowned rows carry the
  same "+" add affordance as search. This is the catalog's existing linkability
  (Layer 1) surfaced as a screen — not the fuller "author profile with bio and
  reviews" feature, which stays `[LATER]`.
- **Notes become a journal, and nothing about them may block stopping the timer**
  (designed 21 Jul 2026, mockups **N1–N5**). Personal notes stay exactly as
  private as rule 13 says, but stop being one overwritable blob per book. The
  way in is a **"✎ Note a thought" pill on the running watch face** (**N1**),
  sitting above Stop & log and never competing with it, carrying a count of the
  notes this sitting already holds — that count is the only way to know they
  exist without opening anything, and it's what makes the Skip copy believable
  later. Tapping it opens **a page, not a sheet** (**N2**) — the scarce resource
  while reading is *room to write*, and a sheet plus a keyboard is a slot. The
  live clock stays pinned to the top of that page, so "the timer never paused"
  is something the reader can *see* rather than a caption they have to trust.
  Pages are optional, start as the one you're on, and widen to a **range**,
  because a thought is usually about a passage rather than a point. The stop
  sheet then grows *one* section listing what you
  already wrote plus room for a closing line, and its Skip says "your 2 notes
  are already saved" — because they are. That's the governing rule made
  concrete: a reader who just wants the timer off is gone in one tap with the
  sitting and every note intact. On the book page (**N4**) notes group under the
  sitting that produced them, so the session header *is* the timestamp; a note
  that came from no sitting keeps its own place rather than being forced into a
  fake one. Private is stated once at the top and never contradicted — unlike a
  review there is no visibility toggle, because there is no other setting.
  **Every note is editable from the history** (**N5**): tapping one in the
  journal opens the same editor it was written in, with only the header swapped
  — the live clock becomes the sitting it came from, which is the context you
  need once the words stop explaining themselves. Editing never re-dates a
  note, or the journal stops being a record and becomes a draft.
- **Stopping the timer asks for one number, and makes it easy to be right**
  (designed 21 Jul 2026, mockups **R1–R3**). The moment after a stop is the only
  one where the reader is holding the book, so it's worth more than an
  `AlertDialog` with a 56px box. The page becomes the screen — a large numeral,
  tappable to type, flanked by **− / +** because being a page or two off is the
  common case — with a live bar and "42 pages this session · 35 pages/hour"
  underneath. The anchor line ("you started this session at p. 260", plus the
  previous sitting) is what makes the number easy to believe; the full log
  (**R3**) sits behind it, not on show, because most stops don't need it. **Skip
  names its consequence** ("keep the time, leave the page at 260") instead of
  being a bare word beside Save. When the catalogue has no page count the total
  gets **its own gold line**, not a second box crammed into the same row — gold
  because it improves the *shared* Edition, and the copy says so. One sheet
  serves all four callers (timer face, mini-bar, Home card, manual log): CLAUDE.md's
  own lesson is that those surfaces drift the moment they're built separately.
- **A chip row is a shortcut, never the vocabulary** (designed 21 Jul 2026,
  mockups **M10–M11**). Type and Genre stay at ~6 visible chips no matter how big
  the catalogue grows: selected values pin first, then the reader's *own*
  most-used, and the honest count beside the label (**All 47 ⌕**) opens a
  typeahead sheet holding the rest. The sheet is the same interaction as the
  author, publisher and original pickers — learned once, reused four times. Its
  real job is **duplicate pressure**: each match carries its book count, so
  "Science fiction · 128" visibly beats inventing "Sci-fi", and creating a new
  genre is the dashed last resort that says out loud the genre is shared (rule
  18). This matters because genres get no server-side case-folding the way Type
  does (`normalize_form` is Type-only) — the sheet *is* the dedupe.
- **The search page before you type shows only things that are true**
  (designed 21 Jul 2026, mockup **4h**): your recent searches (local, private,
  offline), the newest catalogue arrivals filtered to your profile languages, and
  the authors with the most works. Explicitly **no "Trending"** — nothing counts
  reads or views yet, so that row would be sorted by nothing and imply a crowd
  that doesn't exist. When a real reader-count lands it becomes a fourth row
  without moving the others.
- **"Add a book" is four different objects, and the UI must fork before it asks
  for fields** (mapped 21 Jul 2026, mockups **M0–M9**, Area 9). A reader is always
  making one of: a **Work** (not in the catalogue), an **Edition** (a printing of one
  that is), a **Translation** (its own Work, linked), or a **shelf copy** (the only
  *personal* object — Drift-first, the only one that works offline). Authors,
  publishers, genres and series are created *in passing* from free text, never as an
  errand of their own — the pickers exist only to apply duplicate pressure (**M7**),
  and series has no picker at all by design. The branch point is **M1**: the add form
  already asks `works/similar` while you type but discards the answer; that moment
  becomes shelf-copy / new-edition / translation / "different book", phrased in the
  reader's words. Every path ends at one confirmation (**M9**), the only screen that
  can promise offline. Editing is a creation flow too — an edit to someone else's
  Work creates a *revision* (**M5**), so the screen says so in a gold banner *before*
  the reader types, and the inbox shows a diff, not a form (**M6**).
- **A translation is added from the translation's side, never the original's**
  (designed 21 Jul 2026, mockups **T1–T6**, Area 8). The book in your hand is the
  translation, so that's what you add; the original is *context you attach*, not a
  second book you have to own. One optional add-form row — **Translated from**,
  sitting directly under Language because it's a language question — carries both
  cases: pick the original from the catalogue (**T2**), or add it as a four-field
  stub without leaving the sheet (**T3**) when it isn't there yet. The stub is
  catalogue-only; nothing lands on your shelf. Empty = dashed slip-paper row; linked
  = the same gold-ruled card the prefill provenance banner uses (**T4**), and only
  then does **Translator** appear. The original's page carries the mirror entry
  points (**T6**): "＋ Add a translation" (opens the form pre-seeded, links on save)
  next to today's "🔗 Link existing" work-picker. Both sides show two rating numbers,
  never merged — this translation's own average beside "4.2 across all translations"
  (**T5**), the visible form of the locked 5 Jul decision that each translation is
  its own Work with its own rating pool.
- **A linked-author avatar is oxblood + a gold ring; a catalog-only author is a
  flat gold-soft initials circle** (added 14 Jul 2026). Same visual language the
  profile screen already uses for you — an author who's also a registered reader
  gets your treatment, a catalog-only name (an OpenLibrary import, a classic
  author who isn't a Kitabi user) doesn't. Paired everywhere with the same small
  gold "🔗 on Kitabi" pill lending already uses for a linked lender/borrower — one
  badge, one meaning, reused across lending, search, and authorship.
- **The library has two faces — All books and Shelves — and its controls float**
  (added 17 Jul 2026, owner picks: expanding button + S1 tiles). A segmented
  toggle under the title flips between the flat grid and a 2-up wall of shelf
  tiles: built-in shelves from real state (one per non-empty status, plus
  Favourites) followed by every personal tag A–Z and a gold-bordered "+ New
  shelf" door. Each tile fans up to three standing covers on a gold ledge with
  name + count; tapping opens that shelf as a filtered grid (back arrow + shelf
  name replace the title). The header scrolls away entirely — search, filter,
  and sort live on an oxblood circle bottom-right that fans out into labelled
  mini-buttons (`ExpandingFab`), with a gold count badge for active filters
  visible even when collapsed. Personal shelves also appear as a single-select
  SHELF row in the filter sheet, so a shelf composes with status/language/type
  like any other facet. Shelves are personal tags (rule 18) — the catalogue
  never sees them; the chosen view persists per device.
- **The catalogue (Discover/browse) reads like a bookshop wall** (added 18 Jul
  2026, owner request, Apple Books reference). The Books tab is a three-across
  grid of standing covers, each on a gold ledge with its title/author beneath
  and a corner quick-add badge (＋ → moss check once owned). The tall header
  (back + title) steps back on scroll and snaps back the moment you scroll up,
  while the Books ｜ Authors ｜ Publishers tabs stay pinned — so a long
  catalogue never traps you at the top (`NestedScrollView`: a floating/snap
  `SliverAppBar` above a pinned tab bar). The old inline sort/language/type/
  genre dropdown row is gone; search and filter live on the same `ExpandingFab`
  the library uses — Search on every tab, Filter (with an active-facet gold
  badge) only on Books, opening the sort/type/genre/language facets as a bottom
  sheet. Every facet is still applied server-side (the list is paged, so
  narrowing an already-fetched page would hide matches further in). Authors and
  Publishers keep their existing row tiles — only Books gets the cover wall.
- **A book lives on one shelf, picked two ways** (added 18 Jul 2026, refined
  19 Jul — owner rule: *one book, one shelf*). Two sheets share the shelves
  plumbing (personal tags, rule 18). From a book, "Add to a shelf" is a
  single-select radio list of every shelf you have plus a "New shelf" door;
  picking one moves the book there exclusively (off any other shelf) and closes
  the sheet at once — no more type-the-exact-name dialog, no multi-select. From
  a shelf, an opened personal shelf shows an "Add books" button in its header
  whether it's empty or not (empty shelves also get a big centred prompt, and
  the floating control carries the same action), opening a picker that searches
  your whole library and shows under each book the shelf it currently sits on
  (this shelf tinted oxblood, another gold); a tap moves it here or takes it
  off. A search that matches nothing in the library explains that only owned
  books can be shelved and offers a jump to the catalogue to add it first. All
  of it writes straight to Drift and updates live (`libraryTagsProvider`
  streams), and every add/remove enqueues its own sync op.
- **The reading card is one surface; the session history has its own log**
  (added 19 Jul 2026, owner pick "B"). The old separate status/progress and
  reading-session cards merge into one `_ReadingCard`: a tappable status pill,
  a real gold→oxblood **progress bar** over "p. 88 of 200 · 44%", the started
  date with an inline **Edit**, and — while reading — a primary **Start a
  session** with the manual-log as a compact ✎ beside it. Its footer reads
  "Last read {when} · N sessions · {total}" and opens the **reading log** sheet:
  a total, a **week sparkline** (today in oxblood), and every sitting grouped by
  day with its time, the pages it moved through, and its length — each with a
  **delete** for the stray micro-sessions (soft delete, synced). This retires
  the flat "Today · 5s / 3s" rows that used to clutter the card.
- **The book page shows the one shelf as a little bookcase** (added 19 Jul 2026,
  owner pick "B"). The old bare "SHELVES · yours only" + "＋ add" chip row is
  replaced by a ribboned card: a gold bookmark down the edge, the shelf name in
  Fraunces, and a fan of the shelf's *other* books on a gold ledge — the same
  miniature bookcase the Shelves wall uses, so the book page and that grid read
  as one world — with a live "This copy + N others" count and explicit **Move to
  another shelf** / **Remove** actions (Move opens the single-select picker). On
  no shelf, the same card quiets to "Not on a shelf yet · Choose a shelf". The
  fan falls back to the book's own cover when it's the only one on the shelf.

## Screen inventory (v1)

1. Sign in (Google/Apple) · 2. CSV import · 3. Home dashboard · 4. Global search ·
4b. Filter sheet (language/genre/status/year/author/publisher) · 4c. Author page ·
4d. Publisher page · 4e. Search — author match (linked-author 🔗 badge) ·
4f. Author page — on Kitabi (link to the author's public profile) · 4g. Public
Kitabi profile (Library/Works tabs) · 5. Library grid · 6. Book page ·
6c. Share this book (generic per-book card) · 7. Add via ISBN scan ·
7b. Add/edit book form (series + book №, edition-scoped ISBN, format, global
genres, cover upload) · 7c. Add book — author field detects a Kitabi user ·
8. Lending ledger (Lent out tab) · 8b. Borrowed tab (linked + self-logged) ·
8c. Log a borrowed book (bottom sheet) · 9. Lend flow (bottom sheet, now detects
Kitabi users) · 10. Stats (bars + donut + line spark + reading-goal ring) ·
11. Recommendations · 12. Profile (visibility switchboard) · 13. Share card
(personal-endorsement variant) · 14. Quote capture (v1.5 preview, OCR).

Added (14 Jul 2026, owner request — author account linking): 4e/4f/4g and 7c.
Scoped to an invited friend circle of writers (not open sign-up), so there's no
claim/evidence/approval flow in these mockups — the author-field typeahead (7c)
and the author-page (4f) simply reflect an existing `authors.linked_user_id`,
and 4g is the public profile it opens onto. Full plan, including the heavier
claim-based version shelved for if this ever opens beyond invited friends:
`docs/author-identity-and-moderation-plan.md`. 4g is also the first mockup of
the public-profile screen the `GET /users/{id}/profile` /
`GET /users/{id}/library` endpoints already serve — it didn't have one yet.

Revised same day (owner feedback): 4f's link to the profile was a flat text
row that read as dead space — now an outlined `.btn.ghost` button. 4g was
redrawn to reuse the *existing* profile screen (12)'s header exactly rather
than invent a new layout, and "Works by [name]" moved from a static card into
a **Works** tab next to **Library** — the same segmented-control pattern the
lending ledger already uses for Lent out/Borrowed (8b) — so Works is a real
first-class section of the one profile screen, not a bolt-on.

Feature-map audit (3 Jul 2026): every `[V1]` feature now has a home on a screen —
series ordering (7b + search results), share cards (13), full filter set (4b),
manual add/edit path (7b), and all three chart types (10). Good-to-haves added:
personal reading goal (10) and quote capture (14).

Added (4 Jul 2026): borrowed-books shelf, both entry points — linked when the lender
is also a Kitabi user (8b) and self-logged manually (8c) — plus a generic per-book
share card (6c) usable on any book, distinct from the personal-endorsement card (13).
feature-map.md's Layer 2 table, the Layer 4 peer-to-peer row, and wiring rule #2
updated to match: the lending record's user-reference is `[V1]` now, the fuller
social layer (profiles, notifications, requests) stays `[LATER]`.

Added (4 Jul 2026, later same day): author (4c) and publisher (4d) browse pages —
tap a name anywhere to see every catalog work by them. Names in search results, the
book page, and the add/edit form are now tinted oxblood to signal they're tappable.
This is the Layer 1 catalog's existing "linkable" author/publisher entities getting
an actual screen, distinct from the `[LATER]` full profile-page feature (bios,
follows, aggregate author ratings) — feature-map.md's Layer 1, Layer 3, and Layer 4
rows updated to spell out that distinction.

Preview locally: `python3 -m http.server 4173 --directory docs` →
http://localhost:4173/kitabi_screens.html
