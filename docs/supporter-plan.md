# Kitabi Supporter — plan

> Designed 9 Aug 2026, pre-launch. Mockups: [supporter-mockup.html](supporter-mockup.html).
> This is the product design for the second revenue line in
> [revenue-plan.md](revenue-plan.md) §3.2 — written out because the *asking* is
> harder than the *charging*, and getting the asking wrong is how a quiet reading
> app turns into an app people delete.

The ask (owner, 9 Aug 2026): a **"Kitabi Supporter"** membership at **₹149/year**.
Members get a **badge**. Non-members get asked for help — **without being irritated
or disturbed**. Admins must be able to manage memberships and hand out the badge
**without** a subscription.

---

## 0. Short answer on the ₹149

**Yes — ₹149/year, annual-only, one SKU. Keep it.** It's the number
[revenue-plan.md](revenue-plan.md) already landed on, and it's right for three
reasons: it's under the ₹199 psychological step, it's an impulse in India rather
than a decision, and annual-only means no monthly churn micro-decisions for a solo
dev to babysit. What it earns:

| | |
|---|---|
| List price | ₹149/yr |
| Store cut (Apple Small Business / Play first $1M) | −15% |
| Net per supporter, in-app | **~₹127/yr** |
| Net per supporter, UPI on the web | **₹149/yr** (no cut, but manual) |
| All-in running cost of Kitabi | ~₹25–30k/yr |
| **Break-even** | **~200 in-app supporters, or ~170 UPI ones** |

At 1–3% conversion that's 7–20k installs — which is a year out. So the sequencing
matters more than the price (§10): **Phase 1 collects nothing through the stores
and costs nothing to build.**

Three changes I'd make to the brief, in order of how much they matter:

1. **Don't call it "Verified".** Sell the membership, keep the word. §3 — this is
   the one I'd push back on hardest, and it's a two-word fix, not a redesign.
2. **Give the ask a second door: help that isn't money.** §7. It roughly halves
   how extractive the ask feels and it feeds the catalogue, which is the thing
   that actually needs feeding right now.
3. ~~Ship the badge and the admin grant before any payment path.~~ **Overtaken by
   an owner decision, 9 Aug 2026: the subscription is bought and managed *in the
   app*, on both stores, so the membership is bound to the Kitabi account rather
   than to a mail someone remembered to send.** §10 is rewritten around that. It
   is the right call for the reason given — UPI collected on the web can only be
   *linked* to a reader by hand, and a membership nobody can renew without an
   admin isn't a membership. It costs 1½–2 weeks and two store credentials, and
   the store paperwork is the long pole, so it starts on day one.

Everything else in the brief I'd build as stated.

---

## 1. What this is

A **membership**, not a subscription to features. The pitch is the one the revenue
plan already wrote: *keep Kitabi independent, ad-free and not selling you* — with a
mark on your profile and a bigger share of the AI budget as thanks. It absorbs
"donations" (revenue-plan §3.3): there is one mechanism, not two.

**What it must never become:** a paywall around the wedge. Lending, library, sync,
reading sessions, import and **export of your own data** stay free forever, for
everyone, in every version. This is written into §4 as a list the code can be
checked against, because the day someone reaches for "just move export behind
Supporter" is the day the trust positioning dies.

---

## 2. What a supporter actually gets

Only two kinds of thing belong here: **what costs Kitabi money** (so a supporter is
genuinely covering their own weight), and **what costs nothing but feels good**
(so the price is worth paying even to someone who never touches AI).

| | Free | Supporter | Costs us |
|---|---|---|---|
| **The Kitabi seal** on your profile and reviews | — | ✓ | ₹0 |
| **Founding Supporter** mark (first 500, permanent) | — | ✓ | ₹0 |
| **A gold app icon** — the alternate mark on your home screen | — | ✓ | ₹0 |
| **Your ex-libris** — a bookplate on share cards and your profile | — | ✓ | ₹0 |
| **Vellum & Night Library** — two extra paper themes | — | ✓ | ₹0 |
| **Your year in books** — a poster-quality annual broadside | — | ✓ | ₹0 |
| **A vote on what gets built next** | — | ✓ | ₹0 |
| **Early access** — the TestFlight / Play internal track | — | ✓ | ₹0 |
| Name on kitabi.in/supporters (opt-in, off by default) | — | ✓ | ₹0 |
| AI recommendations | 20/day | 60/day | real |
| AI cover-extract | 40/day | 120/day | real |
| *Mood search, shelf-scan, the reading companion* (when they land) | — | ✓ | real |
| **Everything else Kitabi does** | ✓ | ✓ | |

**The perks that sell this are the free-to-run ones, and it's worth being honest
about that.** Almost nobody hits 20 recommendations a day, so "60 instead of 20" is
a weak headline — it's there because it's the line where a supporter genuinely
covers their own weight, not because it converts. What converts a ₹149 membership
is *identity*: a mark on your name, a gold icon on your home screen, a bookplate
with your name on it, and a say in what gets built. All of those cost nothing to
run, which is exactly why they can be given generously.

The three `[LATER]` AI features in the feature map — mood/semantic search,
shelf-scan-to-library, and the spoiler-aware companion — are the expensive ones. As
and when they ship they land supporter-first, because they're the ones with a
per-call bill. That's a pipeline of future value to point at, not a promise to make
in the store listing before it exists.

Notes that are load-bearing:

- **Not "unlimited".** The global daily circuit breaker in
  `services/llm_quota.py` still applies to everyone — a supporter gets a bigger
  share of a bounded pot, never an unmetered path. This is the CLAUDE.md
  metering convention, and premium is not an exception to it.
- **The free quota stays genuinely useful.** 20 recommendations a day is not a
  teaser; nobody hits it in normal use. The ask in §6.2 fires for the reader who
  *actually* burned through it, which is why it can be honest rather than
  manufactured.
- **The bookplate is the best value-for-money item on the list.** An ex-libris
  block ("From the library of ⸻") on the existing share cards costs one widget
  and no running money, and it is exactly the Reading Room's idea of a reward.
- **Nothing here is taken away from anyone.** Every row in the Free column is
  what free readers have today. A supporter tier that quietly degrades the free
  tier to make itself look better is the standard way this goes wrong.

---

## 3. The badge — sell the membership, keep the word "Verified"

This is the one place I'd change the brief. Build it exactly as asked otherwise.

**The problem with a purchasable "verified badge" is not branding, it's lending.**
Kitabi's wedge is that people hand each other physical books. A mark that a reader
reasonably reads as *"Kitabi checked this person"* — when it actually means *"this
person paid ₹149"* — is a mark that helps a stranger get someone's copy of a book
they will not get back. That's a concrete, foreseeable harm, and it lands on the
exact feature the whole product is positioned on.

The repo already holds the other meaning, too: `authors.linked_user_id` and the
`author_claims` queue exist so an author page can say *this really is them*, and
[feature-map.md](../feature-map.md) still lists "verification status / verified
badge" as a Layer-1 data-trust feature. Two different things called the same word,
one of them purchasable, is a collision that gets more expensive every month.

**So: two marks, both admin-grantable, never merged.**

| Mark | Means | Comes from | Look |
|---|---|---|---|
| **The Kitabi seal** | "supports Kitabi" | ₹149/yr, or an admin grant | small gold circular stamp, ❦ |
| **Verified** | "this really is them" | author/publisher claim, admin-approved | the existing `🔗 on Kitabi` family — **never purchasable** |

The seal is a *status* mark and the brief's intent survives intact: it's gold, it's
on your profile, other readers see it, and people will want it. What it isn't is a
claim about who you are.

**It must not collide with the marks already in use** ([screen-design.md](screen-design.md)):

| Existing mark | Already means |
|---|---|
| gold ribbon on a cover | favourite |
| gold ring around an avatar | you / a linked reader |
| `🔗 on Kitabi` gold pill | this counterparty is a registered user |
| moss "Returned" stamp | a closed loan |

A ribbon or a ring would therefore be wrong. The seal is a **circular gold stamp
with the ❦ fleuron** — the app's own flourish, used nowhere else, readable at 14px.

**Three rules that make the seal safe:**

1. **It is tappable, everywhere it appears,** and what it opens says in one
   sentence what it means and — explicitly — what it does not
   (mockup **A4**). One sentence kills the misreading; without it the misreading
   is the default.
2. **It never appears in a lending context.** Not on a loan card, not on a
   counterparty row, not in the lend or borrow sheets, not on the person picker.
   Mockup **A5** is that screen drawn deliberately without it.
3. **Absence is never marked.** No greyed seal, no "not a supporter", no empty
   slot where a seal would go. A free reader's profile is exactly the profile
   they have today.

And one for the reader: **you can turn your own seal off**
(`profiles.supporter_badge_hidden`). Some people pay and don't want a mark; taking
their money and branding them anyway is not the deal.

### Where the seal appears

| Surface | Seal? |
|---|---|
| Your own profile | ✓ |
| Public reader profile — app (4g) and web `/reader/…` | ✓ |
| Review cards — app book page and web book page | ✓ |
| Reader search results, connections list | ✓ (small) |
| **Any lending or borrowing surface** | **✗ — §3 rule 2** |
| Author pages | ✗ — an author gets the *identity* mark there, not this one |

---

## 4. The never list

Checkable claims, not sentiments. If a future change contradicts one of these, the
change is wrong.

1. Lending, borrowing and the whole ledger are free, forever.
2. The library, shelves, tags, notes, ratings, reviews, reading sessions and
   sync are free, forever.
3. **Import and export of the reader's own data are free, forever.** Charging for
   the exit is hostage-taking and it poisons everything else.
4. Offline works identically for everyone. The seal is not checked offline; the
   entitlement is cached and a lapsed one never blocks a read or a write.
5. No free-tier feature is ever removed or degraded to make Supporter look better.
6. No supporter-only ranking, rating weight, catalogue priority or moderation
   privilege. Money never touches catalogue truth (same rule promotions live under).
7. No ads, no ad SDK, no data sold — Supporter exists so this line holds, and
   selling it while breaking it would be the whole point missed.
8. A lapsed supporter loses the seal and the raised quota, and **nothing else**.
   No content locks behind an expiry.

---

## 5. The ask — the anti-irritation contract

The brief's hard requirement. These are numbers, not intentions, and they're
enforced **server-side** (an app-side cap is one reinstall away from being no cap).

**The ask budget**

- **Never in the first 14 days** after the account is created. A reader who
  hasn't finished a book yet has nothing to thank you for.
- **At most 3 asks per year**, and **never two within 60 days**.
- **Dismiss** → nothing for **180 days**.
- **Dismiss twice in a row** → never again, automatically. Nobody has to find a
  setting to be left alone.
- **"Don't ask again"** is one tap, on the ask itself, and is permanent. Honoured
  forever, across reinstalls, because it lives on the profile and not on the device.
- **Promotions opt-out silences it too.** One switch, one promise.
- **Supporters are never asked.** Obvious, and the single most common way these
  systems become insulting.

**Never during**

Onboarding · an active reading session · the timer or its stop sheet · the lend or
borrow flow · the add-book flow · the first launch after an update · a sync error
state · CSV import.

**Never as**

A full-screen takeover · a modal on launch · an interstitial between screens · a
red dot or badge on the tab bar · a countdown · "limited time" · a push
notification · an email (the *only* supporter email is transactional: your
membership expires in 14 days) · a second "are you sure?" after a dismissal ·
anything that isn't dismissible in one tap.

**Mechanically, the ask is a promotion.** It is served by the pipeline built in
Phase 9 — `GET /promotions`, a reserved `kind='supporter'` campaign, targeting,
frequency caps, offline dismissal, the opt-out — with a harder cap on top. There is
no second nag system, no second dismissal store, no second set of rules to keep
honest, and every guarantee above is enforced by code that already exists and is
already tested.

The one exception is the **quota ask** (§6.2), which is not a campaign: it's the
empty state of a screen the reader just walked into by using the feature.

---

## 6. Where the ask appears — three surfaces, in order of honesty

### 6.1 The permanent door (mockups **B1**, **B8**)

A row in Profile: **Support Kitabi**, with the seal glyph. Always there, never
counted as an ask, never a nag — it's the thing that makes the other two surfaces
able to be so rare, because a reader who wants to support you has somewhere to go
on any day of the year.

### 6.2 The quota moment (mockup **B2**)

The reader asked for a 21st recommendation today. The screen has to say something,
and "you've used today's picks" is that something. Adding *"supporters get 60 —
₹149/year"* to a message that was going to exist anyway is the least intrusive ask
in the product, and it's the only one aimed at a reader who is demonstrably costing
money. It carries the reset time, so it's useful even to someone who ignores it.

Capped separately: at most once per 30 days, however often they hit the wall.

### 6.3 The earned moment (mockups **B3**, **B4**)

Once — up to three times a year, 60 days apart, never before day 14 — an inline
card in the Home stream after something genuinely good: a book finished, a year in
review, a fiftieth book shelved. Dismissible, quiet, in the Kitabi voice, and it
leads with what Kitabi is rather than what it costs.

It has **two doors**, and this is the design's whole trick: **Support ₹149/year**
and **Help another way**.

---

## 7. Helping without paying — the second door

Most readers will not pay, and a program that treats them as un-converted revenue
will feel like one. But Kitabi genuinely needs things money can't buy right now —
the catalogue has **0 works with a genre**, most works have no description, and
covers are missing everywhere. That's real help, and it's help the reader can give
in ninety seconds.

**"Help another way"** (mockup **B4**) opens a short list drawn from what this
reader can actually do next:

- **Add a book that isn't here yet** — +10 on the score they already have
- **Fix a cover** — the cover-extract flow, already built
- **Write a review** — the catalogue's thinnest layer
- **Tell one person** — the share card, already built

Two things make this more than a consolation prize:

1. **It's the same reputation score that already exists** (`scoring_service.py`,
   StackOverflow-shaped, already on the profile). Nothing new to build.
2. **Contribution can earn the seal.** An admin can grant a complimentary
   membership to a top contributor — which is exactly the mechanism the brief asks
   for ("allot the badge without a subscription"), pointed at the people who
   deserve it most. The console surfaces contributors as a suggestion list
   (mockup **D2**), so it's one click and not a research project.

That single connection is what makes the seal mean *"this person carries Kitabi"*
rather than *"this person paid"* — which is a better badge, and one that survives
being looked at closely.

---

## 8. Data model

Small. One column does the work; one table keeps the receipts.

```
profiles
  + supporter_until          timestamptz null   -- the entitlement. null = not a supporter
  + supporter_since          timestamptz null   -- first ever became one; drives "Supporter since 2026"
  + supporter_badge_hidden   boolean not null default false
  + supporter_asked_at       timestamptz null   -- last ask shown (server-side frequency cap)
  + supporter_asks_count     int not null default 0
  + supporter_never_ask      boolean not null default false

supporter_grants                       -- the ledger. append-only, soft-delete only
  id                uuid pk
  user_id           uuid → profiles
  source            text     -- 'ios' | 'android' | 'upi' | 'admin'
  amount_inr        int null -- null for a complimentary grant
  period_start      timestamptz
  period_end        timestamptz null  -- null = no expiry (a lifetime grant)
  reason            text null   -- required for source='admin'
  granted_by        uuid null → admins
  revoked_at        timestamptz null
  revoked_by        uuid null → admins
  created_at        timestamptz
  -- store-backed rows only (§10.3/§10.4)
  store_txn_id      text null   -- UNIQUE with source: replayed receipts are no-ops
  store_original_id text null   -- UNIQUE across users: one sub can't light up two accounts
  auto_renewing     boolean not null default false
  raw_status        text null   -- last status seen from the store, for support
```

- `supporter_until = max(period_end)` over the user's live grants — recomputed on
  every grant, revoke and renewal, never edited by hand. `null` period_end wins
  over everything (that's a lifetime grant).
- **A grant is never deleted or edited.** Revoking sets `revoked_at` and
  recomputes. That's rule 3 (soft deletes) and it's also what makes the console's
  history column trustworthy.
- **`profiles` is not a syncable table** — it's the identity row, online-only
  (see the model docstring). The app caches `supporter_until` in Drift so the seal
  and the quota survive offline, and a cached-but-expired entitlement degrades to
  "not a supporter" rather than blocking anything (§4 rule 4).
- **RLS deny-by-default on `supporter_grants`**, zero policies, like every table.
- `llm_quota.quota_for()` grows one parameter — `is_supporter` — and returns the
  raised numbers from §2. The global breaker is untouched.
- Every admin grant and revoke writes to the **existing audit log**. Money-adjacent
  actions with no trail are how a console becomes a liability.

---

## 9. The admin console

A new rail group — **SUPPORT** — visible to `editor` and above; **grant, revoke and
record-a-payment are `super_admin` only**, because they're the two buttons that
move money and the one that hands out status.

**D1 · Supporters** (`/supporters`) — the list. Four KPIs across the top (active,
new this month, expiring in 30 days, annual run-rate), a filter row (All · Paid ·
Complimentary · Expiring · Lapsed), and a table: reader, source, started, expires,
amount, seal state. Search by name, @handle or email. The **Expiring** filter is
the one that earns its keep in Phase 1, where UPI memberships don't auto-renew and
somebody has to send the mail.

**D2 · Reader detail → Supporter card** — the existing reader page grows one card:
current state, the full grant history (source, period, amount, who granted it,
why), and three actions — **Grant complimentary**, **Record a payment**, **Revoke**.
The grant dialog asks for a duration (1 month · 6 months · 1 year · No expiry) and
**requires a reason**, which lands in the ledger and the audit log. The same page
shows the reader's contribution score, so "this person added 40 books, give them a
year" is one screen and not three.

**D3 · Record a payment** — the Phase-1 workhorse. Reader lookup, amount (₹149
prefilled), UPI reference, period (1 year prefilled), note → writes a
`source='upi'` grant. This is how a web supporter becomes a supporter, and it's
deliberately manual: at 150–200 supporters a year that's about four a week, and it
costs no credential, no gateway and no monthly bill (rule 8).

**D4 · Revoke / hide a seal** — revoking asks for a reason and says plainly what it
does (the seal goes, the quota drops, nothing else changes, the reader isn't
notified). Separately, an admin can **hide a seal** without revoking the
membership — the moderation case where someone is using the mark badly. Both land
in the audit log.

**D5 · Supporter dashboard strip** — on the existing dashboard: active supporters,
this month, expiring, run-rate, and the split between paid and complimentary.
That last number is the one worth watching: a program that's 80% complimentary is a
recognition scheme, which is fine, but you should know that's what you built.

---

## 10. The purchase path — in-app subscriptions on both stores

**Owner decision, 9 Aug 2026: the membership is bought and managed inside the app,
so it is bound to the Kitabi account and renews itself.** That means Apple IAP *and*
Google Play Billing — they are two separate systems, and neither sells inside the
other's app. The entitlement crosses over (it lives on the server, keyed to the
Supabase user), but the *purchase* must exist on both.

The shape:

```
app  ──1── store sheet (StoreKit 2 / Play Billing), stamped with our user id
     ──2── purchase token + JWT ──▶  POST /supporter/purchase
                                      3. verify with Apple/Google
                                      4. write supporter_grants row (idempotent)
                                      5. recompute profiles.supporter_until
     ◀─6── entitlement ──▶ seal + raised quotas on every device they sign into
```

### 10.1 Store paperwork — the long pole, so it starts on day one

None of this is code and all of it can block a release. Run it in parallel with
10.2–10.3.

- **Apple:** Paid Applications Agreement signed; banking and Indian tax forms
  complete in App Store Connect (this is the piece that actually takes days).
  Enrol in the **Small Business Program** *before* the first sale — 15%, not 30%.
  Create a **subscription group** with one auto-renewable subscription,
  `in.kitabi.supporter.annual`, priced at ₹149/yr in the India storefront, with a
  localised display name, description and review screenshot.
- **Google:** merchant account set up in Play Console; a **subscription** with one
  annual **base plan** at ₹149. Play's fee is 15% on the first $1M/year.
- Decide the free-trial / intro-offer question now, because it changes the store
  config and the purchase-sheet copy. Recommendation: **no trial.** A ₹149 annual
  is cheaper than the friction of a trial, and trials import churn management.

### 10.2 The app — `in_app_purchase`, not a subscription SaaS

`in_app_purchase` (the Flutter team's own plugin, plus
`in_app_purchase_storekit` / `in_app_purchase_android`) is the right choice: it
wraps both stores, adds no service, no bill and no credential. **RevenueCat is
explicitly out** — it would be faster and it is exactly what rule 8 forbids.

- Add the dependency, the StoreKit configuration file for local testing, and the
  Play Billing permission.
- Check whether StoreKit 2 is on by default in the version you pull — it has been
  an opt-in flag on `in_app_purchase_storekit`, and StoreKit 2 is what makes
  offline JWS verification (10.3) possible.
- One purchase screen (mockup **4b**), one SKU, `queryProductDetails` → `buy`.
  **Price comes from the store, never hardcoded** — the ₹149 in the UI must be the
  localised `ProductDetails.price` or the store will show one number and the app
  another.
- Listen on `purchaseStream`; on `purchased` / `restored`, send the token to the
  API and **only call `completePurchase()` after the server confirms**. Completing
  first means a user who loses the network mid-flow has paid and has nothing.
- `restorePurchases()` on the Membership screen (mockup **9a**) — Apple requires a
  restore path, and a reinstall must return the seal.
- Cache the entitlement in Drift so the seal and the caps survive offline; an
  expired cached entitlement degrades to "not a supporter" and blocks nothing.

### 10.3 The server — verify, don't trust

A purchase token from the app is a claim, not a fact. `POST /supporter/purchase`
takes `{platform, token}`, verifies it, and is the only thing that may write an
entitlement.

- **Apple:** with StoreKit 2 the transaction arrives as a **signed JWS**, which
  verifies *offline* against Apple's root certificates — no API call and no
  credential for the basic check. For renewal status and history you additionally
  want the **App Store Server API**, authenticated with an ES256 key from App
  Store Connect (`kid`/`iss`/`bid` claims) — the same shape as the Supabase JWKS
  verification the API already does.
- **Google:** `purchases.subscriptionsv2.get` on the **Play Developer API**,
  authenticated with a service-account JSON, linked to the Play Console.
- **Idempotency is the whole ballgame.** A unique constraint on
  `(source, store_transaction_id)` — the same reasoning as the sync engine's op
  UUID. A replayed receipt must be a no-op, not a second year.
- Store `original_transaction_id` (Apple) / the base `purchase_token` (Google):
  those are stable across renewals and are what ties every future renewal back to
  the same membership row.

### 10.4 Binding it to the reader — the actual ask

Three mechanisms, and you want all three:

1. **Stamp our user id into the purchase**, so the *store's own* record carries it:
   `appAccountToken` (Apple, a UUID) and `obfuscatedAccountId` (Google). This is
   what makes a support ticket answerable and a refund traceable.
2. **The verification call is authenticated.** The token arrives with the reader's
   JWT, so the server never has to guess whose purchase it is.
3. **A unique constraint on `original_transaction_id` across users.** Without it,
   one Apple ID can buy once, then restore on a second and third Kitabi account —
   the standard way these get farmed. With it, the second restore is refused and
   the console can transfer the membership deliberately if it was a genuine
   account change.

### 10.5 Keeping it current — and the one asymmetry worth knowing

Renewals, cancellations, refunds and billing failures happen *outside* the app,
so something has to keep `supporter_until` honest.

- **Apple hands you a plain HTTPS webhook** — App Store Server Notifications V2,
  a URL you paste into App Store Connect. No infrastructure, no new service.
  `POST /supporter/apple/notifications`, signature-verified.
- **Google's equivalent (RTDN) requires a Cloud Pub/Sub topic** — which is a new
  service and a new credential, i.e. rule 8. **So poll Google instead**: an
  APScheduler job (the scheduler and its job pattern already exist in
  `api/app/jobs/`) re-checks subscriptions expiring in the next few days. At this
  volume a daily pass is ample.

That asymmetry is the single least obvious thing in this whole build, and it is
worth writing down before someone reaches for Pub/Sub to keep the two platforms
symmetrical.

### 10.6 Admin grants do not go away

Everything in §9 stays exactly as designed. Complimentary grants (`source='admin'`)
are how contributors, beta testers, the invited writer circle and library pilots
get a seal — that was in the brief and it's independent of how anyone pays. The
grant ledger simply gains store-backed rows alongside the hand-made ones, and
`supporter_until` is recomputed from all of them the same way.

`source='upi'` also stays in the ledger for the one case that will still happen:
somebody pays you directly and you record it by hand. It is no longer a *path* the
product advertises — just a row an admin can write.

### 10.7 Testing and review

- **Sandbox testers** (App Store Connect) and **licence testers** + the internal
  testing track (Play). Real devices — neither store's purchase flow works
  properly in a simulator.
- Apple's sandbox compresses a year into an hour, so renewal, cancellation, billing
  retry and expiry are all testable in an afternoon. Test them, because §4 rule 8
  (a lapse takes the seal and the quota and *nothing* else) is a claim about code
  nobody will exercise by accident.
- The purchase screen must carry the disclosures Apple checks for: title, length,
  price per period, auto-renew terms, and links to Terms and the Privacy Policy.
  A missing one of these is a routine rejection.
- Review notes need a test account and a description of what the subscription
  unlocks. Whatever the store listing claims must actually exist at review time —
  which is why the `[LATER]` AI perks in §2 are a roadmap, not a listing.

### 10.8 Still never

A payment gateway of our own (a bill, a credential and PCI-adjacent questions for a
₹149 product), monthly billing, or a lifetime SKU — a lifetime membership sells a
decade of revenue for one year's price and buys a permanent support obligation. If
people want to give more later, a second annual tier (**Patron, ₹499**) is the
answer, and not before there's a first one.

---

## 11. Open decisions (owner)

- **The seal's name in the UI.** "Supporter" is the recommendation (§3). If the
  answer is still "Verified", the lending exclusion in §3 rule 2 and the tappable
  explainer in **A4** become load-bearing rather than belt-and-braces.
Owner-only, and mostly paperwork that blocks the build (§10.1):

- **Apple:** Paid Applications Agreement, banking + Indian tax forms,
  **Small Business Program** enrolment, and the subscription group + SKU.
- **Google:** Play merchant account, and the subscription + annual base plan.
- **Free trial or not** — recommendation: **no.** Changes store config and copy,
  so decide before 10.1, not after.
- **Founding Supporter cutoff** — first 500, or everyone in year one? (First 500
  is the recommendation: it's finite, it's a reason to act now, and it lets the
  price rise later without anyone feeling switched.)
- **`supporter@kitabi.in`** — still worth having for support mail, even with no
  web purchase path.
- **GST** — IAP sidesteps it (the stores collect and remit as marketplace
  operators). It only comes back if money is ever taken directly again.
- **Complimentary grants at launch** — the honest use: early testers, the friend
  circle of writers already invited (author linking), and library pilot partners.
- **Which cosmetic perks ship in v1** (§2) — the gold app icon and the two extra
  themes are the cheapest real value on the list, but each is a small design job.

---

## 12. What these mockups commit us to

- The seal is a **gold ❦ stamp**, it means *supports Kitabi*, and it is tappable
  everywhere it appears.
- **"Verified" stays reserved for identity**, and the two marks are never merged.
- **No seal in any lending surface**, ever.
- **Absence is never marked** — a free reader's screens are unchanged.
- The ask is a **promotion**, subject to the caps in §5, enforced server-side.
- **"Don't ask again" is permanent**, lives on the profile, and survives a reinstall.
- **Every free feature stays free** (§4), and export most of all.
- Grants are a **ledger**, not a flag: append-only, reasoned, audited, reversible.
- The membership is **bought in the app on both stores** and bound to the Kitabi
  account three ways (§10.4) — stamped store-side, verified against an
  authenticated call, and made unfarmable by a unique `store_original_id`.
- **Every entitlement is written by the server after verification.** The app's
  purchase token is a claim; nothing the client says sets `supporter_until`.
- **No Pub/Sub.** Apple's webhook is free infrastructure; Google gets polled by the
  APScheduler job that already exists (§10.5).
