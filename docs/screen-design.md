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
  add-book (scan-first).
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
- **Author/publisher names are doors, not just labels** — anywhere a name appears
  (search results, book page, add/edit form), it's tinted oxblood and tappable,
  opening a browse page for everything by that author or publisher. One list
  pattern serves both: chips split owned vs. not (author page) or lean on genre
  (publisher page, since one publisher spans many authors); unowned rows carry the
  same "+" add affordance as search. This is the catalog's existing linkability
  (Layer 1) surfaced as a screen — not the fuller "author profile with bio and
  reviews" feature, which stays `[LATER]`.
- **A linked-author avatar is oxblood + a gold ring; a catalog-only author is a
  flat gold-soft initials circle** (added 14 Jul 2026). Same visual language the
  profile screen already uses for you — an author who's also a registered reader
  gets your treatment, a catalog-only name (an OpenLibrary import, a classic
  author who isn't a Kitabi user) doesn't. Paired everywhere with the same small
  gold "🔗 on Kitabi" pill lending already uses for a linked lender/borrower — one
  badge, one meaning, reused across lending, search, and authorship.

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
