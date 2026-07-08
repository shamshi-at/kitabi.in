# Google Play store listing — Kitabi

Everything to paste/upload into Play Console → Store presence → Main store listing.
Assets in this folder were generated 8 Jul 2026 from the real app on the
Medium_Phone (1080×2400) and Medium_Tablet (2560×1600) emulators, seeded with a
demo library (see the session notes; the demo entrypoint is throwaway and not
committed).

## App name (30 chars max)

> Kitabi — Beyond the Bookshelf

(29 chars. Plain `Kitabi` also fine; the longer form carries the tagline into
search.)

## Short description (80 chars max)

> Every book you own, who borrowed what, and what to read next.

(62 chars — same pitch as the landing page hero.)

## Full description (4000 chars max)

```
Kitabi is a personal library for people who love owning books — a real
bookshelf, finally digital.

Track every book you own, remember who borrowed what, and watch your reading
life take shape. Free, private by default, and built with love for readers in
India and beyond.

YOUR LIBRARY, SHELF BY SHELF
• Add a book in seconds — scan the ISBN barcode, search the catalogue, or type
  it in
• Real editions, not just titles: photograph your own copy's front and back
  covers
• Shelves for Reading, Read, To read, Stopped and Wishlist — plus your own
  private tags
• Track progress page by page, with start and finish dates
• Malayalam, English and more — translations link back to the same work, so
  ഖസാക്കിന്റെ ഇതിഹാസം and its English edition sit side by side

LENDING — NEVER LOSE A BOOK AGAIN
• Lending is a record, not a memory: lent to whom, on which date, due when
• "Out now" and "Returned ✓" at a glance, with a gentle nudge when a due date
  approaches
• Borrowed a book from a friend? Log that too, so it goes home on time

RATINGS, REVIEWS & PRIVATE NOTES
• Rate the books you finish and write reviews when you have something to say
• Personal notes stay on your copy — always private: the edition, the
  condition, why this copy matters

INSIGHTS
• A reading goal you set yourself, and an honest ring that shows the pace
• Books per month, pages per month, and the languages you read in

OFFLINE-FIRST
• Your whole library lives on your phone and works in airplane mode — it syncs
  quietly when you're back online

MOVING IN?
• Import your Goodreads library from a CSV export in minutes

PRIVATE BY DEFAULT
• Your library is yours. Nothing is public unless you choose to share it, and
  there are no ads.

Kitabi — Beyond the Bookshelf. kitabi.in
```

(~1650 chars — well inside the limit.)

## Graphics

| Play Console field | File | Spec |
|---|---|---|
| App icon | `icon-512.png` | 512×512 PNG, 20 KB (≤1 MB) ✓ |
| Feature graphic | `feature-graphic-1024x500.png` | 1024×500 PNG ✓ |
| Phone screenshots (upload in this order) | `phone/phone_01_library.png` … `phone_05_insights.png` | 5 × 1080×1920 (9:16), <8 MB ✓ |
| 7-inch tablet screenshots | `tablet-7/tab7_01…04.png` | 4 × 1920×1080 (16:9) ✓ |
| 10-inch tablet screenshots | `tablet-10/tab10_01…04.png` | 4 × 2560×1440 (16:9) ✓ |

Phone order puts the library shelf first (the wow shot), then Home, Lending,
Book page, Insights. All screenshots are real app screens (Reading Room theme)
framed on the oxblood brand background with a headline — ≥1080 px on every
side, so the listing qualifies for Play's promotion placements (needs ≥4
phone screenshots ≥1080 px ✓).

## Other Play Console fields (not on the listing page but required before publishing)

- **App category:** Books & Reference. Tags: Books, Reading, Library.
- **Contact email:** at.shamshi@gmail.com (public on the listing).
- **Website:** https://kitabi.in
- **Privacy policy URL:** https://kitabi.in/privacy (already live).
- **Content rating questionnaire:** no user-generated public content visible to
  others in V1 (reviews have visibility flags but nothing is public yet), no
  violence/gambling/etc. → expect "Everyone".
- **Data safety:** collects account identifiers (Google/Apple sign-in: name,
  email), user content (library, reviews, notes) synced to the developer's
  server; encrypted in transit; users can request deletion. No ads, no data
  sold, no third-party sharing.
- **App access:** the app requires Google/Apple sign-in → provide a demo
  account for review, or note that reviewers can sign in with any Google
  account.

## Regenerating

- Icon: `sips -z 512 512 app/assets/icon/app_icon.png --out icon-512.png`
  (flat, full-bleed square — Play applies its own mask; do **not** use the
  rounded `landing-page/logo.svg` tile).
- Feature graphic & screenshot frames: HTML templates rendered with headless
  Chrome at exact pixel sizes (`--window-size=… --screenshot=…`); screenshots
  captured via `adb exec-out screencap` from a seeded demo build
  (`lib/main_uidemo.dart`, throwaway) with SystemUI demo mode for a clean
  status bar.
