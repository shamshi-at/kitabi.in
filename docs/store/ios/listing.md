# App Store listing — Kitabi

Everything to paste/upload into App Store Connect → App Information / the
version page. Mirrors [../android/listing.md](../android/listing.md) — same
pitch, same screenshot set, Apple's field shapes. Character limits are Apple's;
counts are given where the copy is near one.

## App Information (set once, not per version)

- **Name (30 chars max):**

  > Kitabi — Beyond the Bookshelf

  (29 chars — same as Play. Plain `Kitabi` also fine; the bundle's
  `CFBundleDisplayName` stays `Kitabi` either way, which is what shows under
  the icon.)

- **Subtitle (30 chars max):**

  > Your library, lending, reading

  (30 chars exactly. This is the App Store's equivalent of Play's short
  description — it renders under the name in search.)

- **Primary category:** Books. **Secondary:** Productivity.
- **Content rights:** does not contain third-party content requiring rights.
- **Age rating questionnaire:** nothing applies → **4+**.

## Version page

- **Promotional text (170 chars max, editable without review):**

  > Every book you own, who borrowed what, and what to read next — a real
  > bookshelf, finally digital. Free, private by default, works offline.

  (≈140 chars.)

- **Description (4000 chars max):** the Android full description with ONE
  edit — App Store Connect rejects the `✓` dingbat ("invalid characters"; it
  treats check marks and emoji alike), so "Returned ✓" becomes "Returned".
  Bullets, em-dashes and the Malayalam title are accepted. Paste this:

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
• "Out now" and "Returned" at a glance, with a gentle nudge when a due date
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

  If the field still complains after this, the next thing Connect's validator
  chokes on varies by account locale — replace the Malayalam title with
  "Khasakkinte Ithihasam" and retry; that has never failed.

- **Keywords (100 chars max, comma-separated, no need to repeat words from the
  name/subtitle):**

  > book,tracker,lending,bookshelf,goodreads,malayalam,isbn,scan,tbr,log,collection,shelf

  (≈90 chars. "library" and "reading" are already in the subtitle, so they are
  indexed for free — spending keyword characters on them is waste.)

- **Support URL:** https://kitabi.in
- **Marketing URL:** https://kitabi.in
- **Privacy Policy URL:** https://kitabi.in/privacy
- **Copyright:** © 2026 Shamshi

## Screenshots

Generated 26 Aug 2026, in this folder — upload as-is:

| Connect slot | Size | Files |
|---|---|---|
| iPhone 6.5″ | 1284×2778 | `iphone-6.5/iphone65_01…05.png` — Library → Home → Lending → Book page → Insights |
| iPad 13″ (required while iPad is enabled: `TARGETED_DEVICE_FAMILY = "1,2"`) | 2048×2732 | `ipad-13/ipad13_01…04.png` — Home → Library → Lending → Insights |

Smaller iPhone/iPad slots scale down from these automatically. If Connect
shows 6.9″ slots instead of 6.5″, it accepts these 1284×2778 files there too.

**How they were made** (to regenerate): the app signed into the test reader
account against the production API on the Android emulator, seeded through
the real flows (7 catalogue books, statuses, four logged sittings — so the
book page shows a *measured* time-to-finish — one loan, a reading goal);
SystemUI demo mode for a clean status bar; `adb exec-out screencap` at
1080×2400, and at 2048×2732 via `adb shell wm size` for the iPad set; the
status-bar strip cropped off (OS-neutral); then composed on the oxblood
brand frame (gold hairline inset, gold eyebrow, Fraunces headline, dark
device mock — same design as `../android/`) by an HTML template rendered
with headless Chrome at exact pixel size. Captions match the Android
listing's word for word.

## App Privacy (the nutrition label — answer once, keep in sync with privacy.html)

Data **collected and linked to identity**, all "App Functionality", none used
for tracking (so no ATT prompt anywhere):

| Apple category | What it is here |
|---|---|
| Contact Info → Name, Email Address | Google/Apple sign-in profile |
| User Content → Other User Content, Photos | Library, reviews, notes; user-photographed covers |
| Identifiers → User ID | Account id; device id for cross-device sync/push |
| Usage Data → Product Interaction | Promotion impression/click/dismiss counts (first-party only) |

Declare **no tracking** (nothing crosses apps/sites; no ad networks). The
promotions row exists because the events carry the account id — first-party
and functional, but still "collected".

## App Review Information

- **Sign-in required:** yes — but there is no password to hand over
  (Google + Apple only). In the demo-account fields write: *"No demo
  credentials exist — the app has no password sign-in. Please use Sign in
  with Apple with any Apple ID; a fresh account is provisioned on first
  sign-in and can be deleted from Profile → Delete account."*
- **Account deletion:** required by guideline 5.1.1(v) since sign-in exists —
  already in the app (Profile), so the answer is simply where it is.
- **Notes worth adding:** push notifications are used for lending nudges,
  reading check-ins and cross-device timer state; the ISBN scanner needs the
  camera (usage string already in Info.plist).

## Before submitting (one-time, outside the listing)

- **APNs production key** uploaded to Firebase (push is dev-only until then —
  STATUS.md tracks this).
- Upload the current IPA via Transporter/Xcode Organizer
  ([../../build.md](../../build.md) §Build a release iOS IPA), then attach the
  build to the version page.
