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
- **Three-way split made visible** on the book page: rating (shared), review (visibility
  control, private by default), notes on dashed "slip paper" (always private).
- **AI stays quiet** — recommendations are cards with a "WHY THIS?" reasoning block
  quoting the user's own ratings; opt-in, with a visible off switch. One labelled
  pick on Home, never a feed.
- **Bottom nav** — Home · Library · [+] · Lending · Insights; oxblood FAB opens
  add-book (scan-first).

## Screen inventory (v1)

1. Sign in (Google/Apple) · 2. CSV import · 3. Home dashboard · 4. Global search ·
5. Library grid · 6. Book page · 7. Add via ISBN scan · 8. Lending ledger ·
9. Lend flow (bottom sheet) · 10. Stats · 11. Recommendations · 12. Profile
(visibility switchboard).

Preview locally: `python3 -m http.server 4173 --directory docs` →
http://localhost:4173/kitabi_screens.html
