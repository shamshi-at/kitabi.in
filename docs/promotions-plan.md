# In-app promotions — plan

**Status: built, 31 Jul 2026** — API, admin console and app, verified on an
Android emulator. Mockups: [promotions-mockup.html](promotions-mockup.html);
checklist in [tasks.md](tasks.md#phase-9--in-app-promotions).

What changed from the design below as it was built:

- **`status` stores intent, not life stage.** Draft / published / paused are
  stored; scheduled, live and ended are derived from the dates on every read
  (`promotion_service.effective_state`). The original three-state design would
  have needed something on a timer to flip rows — and the day it didn't run, a
  finished campaign would still be live.
- **The audience estimate's denominator excludes opted-out readers**, not just
  its numerator. Counting them in one and not the other put "Everyone: 3" beside
  "of 4 readers" on the same panel — two numbers that are each right and together
  read as a bug (caught in the browser, not by a test).
- **Impressions are counted against the enclosing `Scrollable`**, not with a
  visibility package: Home's `ListView` builds every child eagerly, so a
  post-frame callback would have counted a card nobody scrolled to. No new
  dependency for one call site.
- **The reader's opt-out shipped** (§11 recommended it; §13 left it open).

The ask (owner, 31 Jul 2026): once Kitabi is live, be able to push an ad or a
promotion into the app — as a **banner** and as a **card** — that isn't there
by default and appears only when something is created in the admin console,
with **audience targeting** (a Malayalam promo reaches Malayalam readers only),
plus whatever else is worth making configurable.

---

## 1. What this is, and what it deliberately is not

**It is** a first-party, self-served promotion system: Kitabi's own database,
Kitabi's own admin console, Kitabi's own rendering. A promotion is a row you
create, schedule, target, and kill. The app asks the server "anything for me?"
and gets back at most a couple of small JSON objects it already knows how to
draw.

**It is not** an ad network. No AdMob, no Meta Audience Network, no third-party
SDK. That is a firm architectural line, not a preference:

- **CLAUDE.md rule 8** — no new services, no new monthly bills, no new
  credentials. An ad SDK is all three plus a revenue-share account.
- An ad SDK collects an advertising identifier, which pulls in **App Tracking
  Transparency** on iOS, a privacy manifest, a Play Data Safety re-declaration,
  and a consent flow — real work and a permanent tax on every release.
- It surrenders control of what appears in the app. A reading app whose
  positioning is "quiet, private, not a feed" cannot show a mattress ad.

Third-party ads remain possible later; the schema below has a `sponsor` field
so a *paid placement you sold yourself* (a publisher, a bookstore, a lit fest)
works from day one. That's the version that fits Kitabi. Programmatic ads are a
different product decision and would need their own plan.

### Design constraints inherited from the app

The mockups obey these; the code must too.

| Constraint | Why |
|---|---|
| **Never a feed.** At most **one banner + one card** on screen at once, ever. | The whole product argument (feature-map.md's three strategic warnings) is that Kitabi is calm. A promo *stack* would be the loudest thing in the app. |
| **Always labelled.** "From Kitabi" or "Sponsored" — never unlabelled, never disguised as a book. | Store policy on both platforms, and the reader's trust is the asset. |
| **Always dismissible**, and dismissal sticks across devices. | A promo you can't close is the thing people uninstall over. |
| **Reading Room theme only** — paper/ink/oxblood/gold, `docs/screen-design.md` tokens. No advertiser artwork controlling the frame. | An ad that looks pasted-in makes the whole app look cheap. Images live *inside* a Kitabi-drawn card. |
| **Never on top of the reading experience.** No promos on the reading timer, the book page's Yours tab, or any modal. | Interrupting someone mid-sitting is how you get uninstalled. |
| **Nothing renders when nothing is live.** No placeholder, no empty slot, no reserved space. | Same rule that just bit Home's "Fresh on your shelf": a section heading over a hole reads as broken. |

---

## 2. The two surfaces

### The banner — a thin strip, top of Home

Sits directly under the Home header, above "Currently reading". One line of
text, an optional small mark, a chevron, and a dismiss ×. It is the *quiet*
placement: an announcement ("Kitabi is on Android now", "Trivandrum Book Fair,
5–9 Aug"), not a pitch.

- Height ~44–52pt, single line, truncates rather than wraps.
- Never pushes the currently-reading card below the fold on a small phone —
  which is why it's a strip and not a box.
- Dismiss is a real × at the trailing edge, not a swipe-only gesture.

### The card — a full block in the Home stream

Sits in the Home `ListView` between "Your shelves" and the quote card — the
slot the recommendations entry (`_RecsEntryCard`) already occupies when opted
in, and the same visual weight. It is the *rich* placement: image or book
cover, a headline in Fraunces, two lines of body, one CTA.

Three card shapes, all Kitabi-drawn:

1. **Book-led** — a real catalog Work: cover, title, author, "Look inside".
   Taps deep-link to the book page. This is the highest-value shape and the one
   most likely to be used.
2. **Image-led** — a 16:9 image with the headline overlaid on a scrim.
3. **Text-led** — no artwork, Fraunces headline on gold-soft or dark panel.
   Renders instantly, works offline, and is the fallback when an image fails.

### Later placements (wired, not built)

`placement` is a column, not an if-statement, so these cost nothing now:
`discover_top` (Catalog browse), `library_footer`, `insights_footer`. Home is
the only one that ships in v1 — one surface done properly beats four half-done.

---

## 3. Data model

Three new tables. Server-only, cross-user, **not** `SyncableMixin` — a
promotion is not the reader's data, it's ours (same category as the catalog:
CLAUDE.md rule 2). RLS enabled with zero policies like every other table
(rule 11). One Alembic migration, next in sequence: **`000034_promotions`**.

### `promotions` — the campaign

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | server-assigned; not a syncable entity, so rule 4 doesn't apply |
| `kind` | text | `banner` \| `card` |
| `card_style` | text \| null | `book` \| `image` \| `text` (cards only) |
| `placement` | text | `home_top` \| `home_stream` (+ the wired ones above) |
| `status` | text | `draft` \| `scheduled` \| `live` \| `paused` \| `ended` |
| `priority` | int | higher wins when several match; ties break on `starts_at` |
| `sponsor` | text \| null | null = "From Kitabi"; set = "Sponsored · {sponsor}" |
| `starts_at` / `ends_at` | timestamptz | UTC (rule 5); null `ends_at` = runs until stopped |
| `targeting` | jsonb | §4 |
| `frequency` | jsonb | §6 |
| `work_id` / `edition_id` | uuid \| null | for book-led cards — FK into the catalog |
| `created_by` / `updated_by` | uuid | `admin_users.id` |
| `created_at` / `updated_at` / `deleted_at` | timestamptz | soft delete only (rule 3) |

### `promotion_contents` — the copy, once per language

**This is the piece that answers "a Malayalam ad should reach Malayalam
readers".** It's two mechanisms, not one, and keeping them separate is what
makes the feature good:

- **Targeting** (§4) decides *who is eligible*.
- **Content variants** decide *which words they see*.

One row per `(promotion_id, language)`, with `language = null` as the default
variant.

| Column | Notes |
|---|---|
| `language` | `'Malayalam'`, `'English'`, … from `app/lib/core/languages.dart`; null = default |
| `headline`, `body`, `cta_label` | the copy |
| `image_url` | optional; §9 |
| `action_type` | `deep_link` \| `external_url` \| `none` |
| `action_value` | `/book/:workId/:editionId`, `https://…`, or null |

So a single "Onam reading sale" campaign carries Malayalam *and* English copy,
and each reader gets theirs. And a campaign that is *only* relevant to
Malayalam readers simply targets `languages: ["Malayalam"]` and ships one
variant. Both cases fall out of the same structure.

Resolution order for a reader: first `preferred_languages` entry with a
variant → default variant → skip the promotion entirely if neither exists.

### `promotion_events` — append-only engagement

| Column | Notes |
|---|---|
| `id` | uuid — **client-generated**, unique constraint, so a retried batch is idempotent (same rule the sync engine's op UUIDs follow) |
| `promotion_id`, `user_id` | |
| `kind` | `impression` \| `click` \| `dismiss` |
| `occurred_at` | when it happened on the device, UTC |
| `received_at` | server clock |

Everything else is derived from this table: the metrics panel, frequency caps,
and dismissal state (`kind = 'dismiss'` exists → never serve again). A partial
index on `(user_id, promotion_id) WHERE kind = 'dismiss'` keeps the serve query
cheap. `# SCALE:` if event volume ever makes that COUNT slow, materialise a
`promotion_reader_state` row — in Postgres, not Redis (rule 8).

---

## 4. Targeting — the full configurable surface

All of it evaluated **server-side**. The device never receives a promotion it
isn't eligible for. Three reasons, and the first is the important one:

1. **Privacy and leakage** — client-side filtering means shipping every
   campaign and every targeting rule to every device. That leaks your
   commercial plans to anyone with a proxy.
2. **Payload** — one or two objects instead of the whole table.
3. **You can retarget without an app release.**

`targeting` is a JSONB object; every key is optional and an absent key means
"don't filter on this". All present keys must match (AND); values within a key
are OR.

| Key | Example | Source | Ships v1 |
|---|---|---|---|
| `languages` | `["Malayalam"]` | `profiles.preferred_languages` — already captured at onboarding, already drives Discover | ✅ **the headline feature** |
| `platform` | `["android"]` | needs a new `X-Platform` header on the API client (§7) | ✅ |
| `app_version_min` / `max` | `"0.2.0"` | `X-App-Version`, already sent on every request | ✅ |
| `account_age_days` | `{"max": 7}` | `profiles.created_at` — "new readers only" | ✅ |
| `library_size` | `{"min": 10}` | COUNT of active `library_entries` | ✅ |
| `has_status` | `["reading"]` | reader has ≥1 entry in that status | ✅ |
| `genres` | `["Fiction"]` | genres of works in their library | ✅ |
| `reader_ids` | `["uuid…"]` | explicit list — **how you test a promo on yourself before it goes wide** | ✅ |
| `rollout_percent` | `25` | stable hash of `(promotion_id, user_id)` — same reader always lands the same side | ✅ |
| `exclude_reader_ids` | | | ✅ |
| `authors` | `["Perumal Murugan"]` | authors in their library | later |
| `country` | | **deliberately not collected** — see below | ✗ |

**No country/geo targeting, and no device fingerprinting.** Kitabi doesn't
store a country and shouldn't start: it would mean either an IP-geolocation
service (a bill and a credential — rule 8) or inferring from locale/timezone,
which is exactly the fingerprinting posture the app's privacy stance rejects.
`languages` is a better proxy for the actual use case *and* it's data the
reader gave you on purpose. If a genuinely geo-bound campaign comes up (a book
fair in one city), use `reader_ids` or accept a wider audience.

### Audience estimate

The composer shows a live count — "**~412 readers match**" — recomputed as
rules change (htmx partial, same pattern as the console's existing search).
It runs the same SQL the serve path runs, minus the frequency and dismissal
clauses. Without it, targeting is guesswork, and you find out you targeted
nobody after the campaign ends.

---

## 5. Serving — the API

### `GET /promotions`

Returns the promotions this reader should see *right now*, already resolved:
targeting applied, language variant chosen, dismissals and caps excluded,
priority sorted, capped at one per placement.

```json
{
  "version": "8f2c1a",
  "promotions": [
    {
      "id": "…", "kind": "banner", "placement": "home_top",
      "sponsor": null,
      "headline": "Trivandrum Book Fair — 5 to 9 August",
      "body": null, "cta_label": "See what's on",
      "image_url": null,
      "action_type": "external_url", "action_value": "https://…",
      "dismissible": true,
      "expires_at": "2026-08-09T18:30:00Z"
    }
  ]
}
```

- **`version`** is a hash of the resolved payload, returned as an `ETag`. The
  app sends `If-None-Match` and normally gets a **304** — a few bytes per poll.
- **`expires_at`** lets the cached copy die on the device without a network
  call, so a finished campaign disappears offline too.
- Called at app foreground, at most once every 30 minutes, and after sign-in.
  Never blocking: Home renders from Drift and updates when the response lands.

### `POST /promotions/events`

Batched array of events. Idempotent on the client-generated event id. Returns
204. Fire-and-forget from the app's point of view.

### Admin-facing

The console reads and writes the tables directly through the shared SQLAlchemy
models (`admin/console/bootstrap.py` already puts `api/app` on the path) — no
internal HTTP API, same as every other console section.

---

## 6. Frequency, fairness, and the rules of engagement

`frequency` JSONB on the promotion:

| Key | Default | Meaning |
|---|---|---|
| `max_impressions` | `null` | stop after N views by this reader |
| `min_hours_between` | `24` | cooldown so the same promo isn't on every launch |
| `dismissible` | `true` | false only for genuinely critical notices (a service outage) |
| `redisplay_after_days` | `null` | null = a dismissal is permanent |

**Caps are approximate across devices, exactly on one.** The client counts its
own impressions in Drift and enforces locally; the server enforces from
received events. A reader on two phones, offline, can see one extra
impression. That's the honest tradeoff for offline-first, and it is not worth a
synchronous check before every render. Documented here so nobody later reads it
as a bug.

**One banner and one card, maximum.** The serve query picks the highest
`priority` per placement and drops the rest. If two campaigns tie, the older
`starts_at` wins — a deterministic rule beats a random one when you're debugging
"why didn't mine show".

---

## 7. The app

### Data layer

New Drift table `CachedPromotions` — plain cache, sibling of `CachedBooks`
(`app/lib/data/db/tables.dart`), **not** a `SyncColumns` table:

```
id, kind, cardStyle, placement, sponsor, headline, body, ctaLabel,
imageUrl, actionType, actionValue, dismissible, priority,
expiresAt, fetchedAt, dismissedAt, impressionCount, lastShownAt
```

Plus `PromotionEventQueue` — a small local outbox (`id`, `promotionId`, `kind`,
`occurredAt`, `attempts`).

**Why the event queue is not the sync queue.** The sync engine exists for
Layer-2 entities that get updated and deleted and therefore need op ordering,
`server_seq` cursors, LWW conflict resolution and conflict-history rows. Promo
events are append-only facts with a client-generated id and no conflicts. Reusing
`sync_queue` would drag all that machinery into a case that needs none of it — and
would put marketing telemetry in the same retry path as a reader's library, where
a promo-server hiccup could stall real data. Separate outbox, its own simple drain
(max 5 attempts, exponential backoff, then drop — losing an impression count is
not worth a permanent queue).

### Providers and widgets

```
features/promotions/
  providers/promotions_providers.dart   # StreamProvider over Drift
  widgets/promo_banner.dart
  widgets/promo_card.dart
  promotions_repository.dart            # fetch → cache; dismiss → local + queue
```

The provider must be a **`StreamProvider` over a Drift watch**, not a
`FutureProvider` — dismissing from the banner has to update Home without the
caller invalidating anything. That exact mistake has been made three times in
this repo (`cachedBookProvider`, `libraryTags`, `libraryEntryProvider`); the
lesson is in CLAUDE.md and applies here verbatim.

### Rendering rules

```dart
// in _Dashboard.build, following the pattern already used for
// `if (reading.isNotEmpty)` and `if (activeLent.isNotEmpty)`
if (banner != null) PromoBanner(promo: banner),
...
if (card != null) PromoCard(promo: card),
```

Nothing to hide, nothing to reserve. An impression is logged when the widget is
actually **visible** (a `VisibilityDetector`-style check or a post-frame
callback on first build), never on fetch — counting impressions for a promo
that never got scrolled to would make every metric a lie.

### Offline

Everything renders from Drift, so promos work in airplane mode until
`expires_at`. Dismissal writes `dismissedAt` locally and immediately, then
queues the event. Images are cached by the same `CachedNetworkImage` path
covers already use; **a card whose image hasn't loaded renders as the text-led
shape rather than a grey box.**

---

## 8. The admin console

A new nav group **Promotions** in `admin/console/templates/base.html`, between
Moderation and Catalog, restricted to `ROLE_EDITOR` and above (a moderator
handles reports; publishing to every reader's Home is an editor's job). Every
create/edit/publish/pause writes an `AdminAuditLog` row like every other
mutation in the console.

```
admin/console/routers/promotions.py
admin/console/templates/promotions.html       # list
admin/console/templates/promo_edit.html       # composer
admin/console/templates/_promo_preview.html   # htmx phone preview
admin/console/templates/_promo_estimate.html  # htmx audience count
```

Five screens (mocked in `promotions-mockup.html`):

1. **List** — grouped Live / Scheduled / Draft / Ended, each row showing
   placement, audience summary in words ("Malayalam readers on Android"), the
   schedule, and impressions/clicks so far.
2. **Composer — content** — kind, style, copy, image, CTA, and a
   **language-variant tab strip** (Default · Malayalam · +) so the Malayalam
   copy is written right next to the English.
3. **Composer — audience** — the targeting rules as plain-language rows, with
   the live estimate pinned beside them.
4. **Composer — schedule & frequency** — start/end in IST (stored UTC), caps,
   cooldown, dismissibility.
5. **Live preview** — the actual phone frame, switchable between language
   variants and between banner/card, so you see what a reader sees before you
   publish.

Plus a **Stop now** button on every live promo that sets `status = paused` in
one click with no confirmation dialog — when a promo is wrong you want it gone
in one tap, and pausing is reversible.

---

## 9. Images

`image_url` is a plain URL column, so the *schema* doesn't care where images
live. Two ways to fill it, in order of preference:

**Built: the existing Supabase Storage `covers` bucket.** Not a new store —
the app has uploaded book covers, author portraits (`authors/…`) and publisher
logos (`publishers/…`) there since Phase 2
(`app/lib/features/catalog/catalog_image_upload.dart`), and
`extraction_service` already validates cover URLs against it. The console
writes to the same bucket under `campaigns/…` via the Storage REST API
(`admin/console/assets.py`, plain httpx), with `SUPABASE_SERVICE_ROLE_KEY` as
the operator credential.

> **Correction, 31 Jul 2026.** This section first recommended a second
> Cloudflare R2 bucket with boto3, on the strength of a line in CLAUDE.md
> claiming there was no Supabase bucket. There was — and it already held the
> exact two things this feature needed, author portraits and publisher logos.
> The R2 path was built and then removed; that CLAUDE.md line is now fixed.
> The lesson is the cheap one: **check the code before trusting a doc about
> what doesn't exist yet.** R2 stays the encrypted-backup target and nothing
> else.

**Dormant until configured**, like the mail transport: without the service-role
key the console hides the upload control, names the missing variable and says
to paste a URL. A campaign image that 404s still degrades to the text-led shape
(§7), so a bad URL costs nothing.

---

## 10. Metrics

Per promotion, straight out of `promotion_events`: impressions, unique
readers reached, clicks, CTR, dismissals, dismissal rate. Per language variant
too — that's how you learn whether the Malayalam copy actually worked.

The number to actually watch is **dismissal rate**. Click-through tells you a
promo was interesting; dismissal rate tells you it was unwelcome. A campaign
over ~20% dismissals is doing brand damage regardless of its clicks, and the
list screen should show it in oxblood when it crosses that line.

---

## 11. Privacy, policy, and disclosure

- **No new personal data is collected.** Targeting reads what the reader
  already gave you (languages, their own library). No advertising ID, no IP
  geolocation, no cross-app tracking — so **no ATT prompt**, no privacy-manifest
  tracking domains, and the Play Data Safety form barely changes.
- **Every promotion is visibly labelled** — "FROM KITABI" or
  "SPONSORED · {sponsor}" in the same small-caps treatment section labels use.
  Both stores require paid placements to be identifiable; more importantly, an
  unlabelled promo in a reading app is a trust bomb.
- **Never target on inferred sensitive attributes.** Language here is a reading
  preference the reader typed in, not an ethnicity proxy — keep it that way and
  don't add rules that would make it one.
- **Privacy policy needs one paragraph** (the landing page already hosts one):
  that Kitabi may show its own promotions, that they're chosen on the server
  from your language and library, and that engagement is counted. Ship that
  paragraph in the same release as the feature, not after.
- **Add a settings toggle: "Show promotions from Kitabi."** Not required by
  anyone — but an app that positions itself against the attention economy and
  then makes its promos unavoidable is arguing with itself. Default on, one
  switch in Profile, respected by the serve query.

---

## 12. Deliberately not in v1

| Deferred | Why |
|---|---|
| Third-party ad network | §1 |
| Push-notification promos | The FCM stack exists (`push_service`, `device_tokens`), but a promo *push* is a different consent conversation and a much easier way to get uninstalled. Separate decision. |
| A/B testing of variants | `rollout_percent` gives crude splits; real experiment tooling is a project. |
| Rich/HTML promo bodies | An HTML renderer in the app is an injection surface and a theme-consistency nightmare. Structured fields only. |
| Reader-segment builder UI | v1 targeting is a fixed set of rules in a form. A visual segment builder is admin-console scope creep. |
| Scheduling by timezone per reader | Stored UTC, entered IST, shown to everyone at the same instant. |

---

## 13. Open decisions for the owner

1. **Sponsored placements — yes or no?** The schema supports both; the answer
   changes the *label* and whether store "paid content" rules engage. Default
   assumption: build the field, run only Kitabi's own promos at launch.
2. **Images: R2 bucket now, or paste-a-URL for v1?** §9 recommends R2.
3. **The opt-out toggle in §11** — ship it or not. Recommendation: ship it.
4. **Does a promo ever get to interrupt?** This plan says no — no modals, no
   full-screen takeovers, ever. If a launch-day announcement needs more reach
   than a Home banner, that's what the banner's `dismissible: false` is for.

---

## 14. Phasing — where this lands in `docs/tasks.md`

Post-launch, as its own phase (**P9 — Promotions**). Order matters; each step
is shippable on its own.

| Step | Scope | Rough size |
|---|---|---|
| **P9.1** | Migration `000034`, three tables + models, RLS on | small |
| **P9.2** | `GET /promotions` + `POST /promotions/events` with targeting, variants, ETag; service-layer unit tests for every targeting rule | medium — **the targeting resolver is the piece to test hardest** |
| **P9.3** | Admin console: list + composer + preview + audience estimate + audit | medium |
| **P9.4** | App: Drift cache, repository, providers, banner + card widgets, event outbox, Home wiring | medium |
| **P9.5** | Metrics panel; privacy-policy paragraph; settings opt-out | small |
| **P9.6** | `X-Platform` header on `ApiClient`; verify on a real device with a real campaign end-to-end | small |

**P9.6 is not optional.** The last three owner-reported bugs in this repo
(the timer's page save, the Live Activity deep link, the wax-seal styling) all
passed their tests and failed on the phone. A promo system's whole job is to
render correctly on someone else's device — the definition of done is a real
campaign, created in the console, appearing on a real phone, dismissed, and
gone.

---

## 15. Rules this must obey

- **Rule 2** — promotions are server-authoritative, cached in Drift for offline
  reading, never synced as user entities.
- **Rule 3** — soft delete; a promotion is never `DELETE`d.
- **Rule 5** — all timestamps `timestamptz` UTC; IST only at the console's
  input and the app's rendering.
- **Rule 8** — no new service. R2 and Postgres are already here; nothing else
  is needed.
- **Rule 11** — RLS enabled, zero policies, on all three tables.
- **All user-facing strings through l10n arb**, including the "From Kitabi" and
  "Sponsored" labels — Malayalam localisation is on the roadmap, and a
  promotions feature that hardcodes English is a bad joke given the whole point
  of §4.
