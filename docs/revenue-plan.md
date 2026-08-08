# Revenue & running-cost plan

> Written 8 Aug 2026, pre-launch (Play internal testing + TestFlight, web platform
> live). This is a plan, not a spec — each line that becomes real work gets its own
> entry in [tasks.md](tasks.md) and, where product-shaped, in
> [../feature-map.md](../feature-map.md). Numbers marked ~ are estimates to be
> replaced with observed reality.

## 0. Framing — three constraints every idea must pass

1. **The positioning stays.** Lending + library + sync are the billboard and stay
   free forever; AI is the quiet delight (the 2026 market is AI-wary). Nothing
   below paywalls the wedge, and nothing sells user data or attention to third
   parties — trust *is* the product's moat.
2. **Rule 8 still applies.** Revenue features must not add standing bills or
   fragile credentials ahead of the revenue itself. (An Amazon associate *tag* is
   config; the PA-API is a credential with eligibility requirements — first one
   yes, second one no.)
3. **Solo maintenance.** Every revenue line is also a support burden. Prefer lines
   that scale with traffic (affiliates, SEO) or with a handful of high-touch
   relationships (libraries, publishers) over lines that scale with ticket volume.

**The honest thesis:** consumer revenue in India (affiliates + premium) covers the
infra bill at best in year one. The first line that pays *real* money is B2B —
libraries, then publishers — and both need the consumer product to be credible
first. So: ship the cheap consumer lines now, validate B2B with zero-build
funnels, and don't let B2B distract from launch.

---

## 1. What Kitabi costs to run — and how it stays flat

| Item | Cost | Notes |
|---|---|---|
| Railway (api + admin) | ~$5–15/mo usage-based | The only true metered infra bill. Two small services, Singapore |
| Supabase | ₹0 (free tier) | Watchlines: 500 MB DB (catalog growth), 1 GB storage (covers bucket), ~5 GB/mo egress (covers — the edge cover proxy + Cache API keeps repeat reads off Supabase; keep cache lifetimes long) |
| Cloudflare (Pages, DNS, edge) | ₹0 | Whole public web runs here |
| OpenLibrary, IndexNow, FCM | ₹0 | No-credential choices already made |
| Anthropic (recs + cover-extract) | usage, **ceiling is configured** | `llm_usage` + `services/llm_quota.py`: per-reader daily quota + **global daily circuit breaker** — the max daily bill is a setting, not a hope |
| Apple Developer Program | $99/yr | |
| Google Play | $25 once | Paid |
| Domain kitabi.in | ~₹800/yr | |

**All-in: roughly ₹25–30k/yr (~₹2–2.5k/mo).** That is the break-even target, and
it's small enough that a single revenue line can cover it.

Cost controls, mostly already built:

- **Every paid endpoint is metered** (CLAUDE.md convention). Premium never removes
  metering — it raises quotas. The global breaker stays the hard ceiling.
- **Model tiering:** cover-extract runs `claude-sonnet-5` with thinking disabled.
  Worth an A/B against Haiku 4.5 (~⅓ the price) — transcription is Haiku-shaped
  work; keep recs on the stronger model, they're the delight feature.
- **Prompt caching** on the recs system prompt when volume appears.
- Free-tier watchlines above go on the ops checklist; the first thing likely to
  cost money at real traffic is Supabase egress for covers — the answer is edge
  cache headers, not a new service.

---

## 2. The honest revenue math (why the sequencing below)

| Line | Year 1, realistic | At scale | Scales with |
|---|---|---|---|
| 1. Affiliate links | ₹0–6k | grows with search traffic | SEO (already built, needs Search Console + content depth) |
| 2. Premium ("Supporter") | ₹0–15k | ₹1L+/yr at 10–20k MAU | Installs × 2–5% conversion × ₹149–199/yr |
| 3. Donations | noise | noise | — (fold into Supporter) |
| 4. Library licences | ₹0 (pilots) | ₹30–80k/yr at 10 libraries × ₹3–8k | Sales conversations, not traffic |
| 5. Publisher tools | ₹0 | ₹50k–1L/yr later | Provable audience |

Break-even needs **either ~6–8 paying libraries or ~150–200 Supporter annuals**.
The first is ten conversations in Kerala; the second is thousands of installs.
Both are plausible; the library line gets there first, which is why it's the one
to *validate* early even though it's built last.

---

## 3. The five ideas, judged

### 3.1 Affiliate buy links — **yes, build first** (days of work)

The best idea on the list, and it's fully automatable today:

- **ISBN-10 = Amazon ASIN for most printed books**, and `services/isbn.py` (5 Aug)
  already derives ISBN-10 from ISBN-13. So a "Buy on Amazon" link is
  `https://www.amazon.in/dp/<ISBN10>?tag=<associate-tag>` — a URL template, no
  API, no credential, no scraping. Fallback for 979-prefixed ISBNs (no ISBN-10
  exists) and no-ISBN editions: a tagged search URL
  `https://www.amazon.in/s?k=<ISBN13 or title+author>&tag=<tag>`.
- **Skip the PA-API deliberately** (credential + "3 qualifying sales" eligibility
  + quota tied to revenue — rule 8 says no). Plain tagged URLs need only the tag.
- **Serve the links server-side** — in the `/public/book` payload for the web and
  the catalog payload for the app — so the tag, retailer list, and ordering are
  config edits, never app releases. One `buy_links` builder in the API, rendered
  as a "Get this book" block on the web book page and a row on the app book page.
- **Why it's first:** zero marginal cost, zero App Store entanglement (physical
  goods — Goodreads precedent), and it monetizes **non-users** via the web
  platform's SEO pages, which is the only line that earns while the install base
  is small.
- **Bounties beat commissions:** Amazon Associates India pays flat bounties for
  Kindle Unlimited / Audible signups — a "Read on Kindle" link on a book page can
  out-earn the low single-digit % on a paper copy. Check the rate card at signup.
- **Flipkart needs an aggregator, and that's now wired** (8 Aug 2026). Flipkart
  closed its *direct* affiliate programme to new publishers years ago, so there
  is no `affid` to go and get — the reachable route is a network. **Cuelinks**
  is the one that fits this architecture: free, India-only, no stated traffic
  minimum, and its **Link Kit is a pure URL template**
  (`linksredirect.com/?cid=<CID>&source=linkkit&url=<encoded>`), so the server
  can build it with no snippet, no client JS and no API call at render time —
  their Chrome-extension/WordPress-plugin route would have broken both the
  "content is server-rendered" and "no third-party script" rules. Set
  `CUELINKS_CID` and the generated Flipkart link is wrapped; leave it unset and
  the link stays plain and useful. Deliberately scoped: the wrapper touches
  **only the generated Flipkart link** — never Amazon (a direct tag gives away
  no cut to a middleman) and never a stored contributor link (whose merchant may
  not be in the network at all). One CID would also unlock other book retailers
  in the network later, which is the reason to prefer it over EarnKaro/ExtraPe
  (creator-focused, link-at-a-time, nothing to automate against).
- **Compliance:** visible disclosure ("Kitabi may earn a commission from these
  links") on web pages and the app screen that show them; no cloaked links; no
  tagged links in push/email (Associates ToS). Amazon Associates requires ~3
  qualifying sales within 180 days to keep the account — expect to re-apply once.

**Expectation:** covers the domain, not the infra, until search traffic is real.
It's a compounding asset bolted onto the SEO work that's already live.

### 3.2 Premium membership — **yes, second; the metering is 80% of the build**

- **What's premium:** exactly the features with marginal cost — AI extraction and
  recommendations beyond the free daily quota. The free quota stays genuinely
  useful (the delight hook must remain reachable by everyone); premium raises or
  removes the per-reader cap. The global circuit breaker still applies to
  everyone — premium is a bigger share of a bounded pot, never an unmetered path.
- **Sell it as "Kitabi Supporter", not "AI plan".** AI-wary market; "keep Kitabi
  independent and ad-free, get unlimited AI as thanks" is the right pitch — and
  it absorbs idea #3 (donations) into one mechanism. A quiet supporter flourish
  on the profile (the reputation system already exists) fits the Reading Room
  brand.
- **Cheap now:** add `profiles.premium_until` (one migration) and make
  `llm_quota.quota_for()` consult it. Dormant until a purchase path exists, but
  the entitlement plumbing stops being a blocker later.
- **Expensive later:** the purchase path. iOS requires IAP for digital features —
  StoreKit 2 + Play Billing + server-side receipt verification (App Store Server
  API + Play Developer API; two unavoidable credentials). RevenueCat would be
  faster but is a new service + bill (rule 8) — go direct. ~1–2 weeks. Enroll the
  **Apple Small Business Program** (15% not 30%); Play subs are 15%.
- **Price India-first:** ₹99–199/**year**, annual-only to start — one SKU, no
  monthly churn micro-decisions, trivially cheap against any competitor.
- **Timing:** post-launch v1.x. Premium before there are users is pure overhead;
  launching free also gives the quota settings real usage data to price against.
- **Never premium:** lending, library, sync, import/export of the reader's own
  data (export behind a paywall reads as hostage-taking and poisons the trust
  positioning).

### 3.3 Donations — **fold into Supporter, don't build separately**

- On iOS an in-app "tip the developer" must itself be an IAP (Apple's cut
  applies), and an external donate link inside the app is a 3.1.1 rejection
  risk. Two payment mechanisms for one revenue line isn't worth the review
  surface; donations also undercut the Supporter pitch ("why subscribe when I
  can tip ₹20 once?").
- **Do instead:** the in-app "Support Kitabi" surface *is* the Supporter
  subscription. On the **website/landing page** (outside store jurisdiction), a
  quiet UPI / Buy-Me-a-Coffee link costs an hour and is fine — some web visitors
  will never install the app.

### 3.4 Library licensing — **the real money; validate now, build later**

Strongest revenue idea on the list, truest to the roots (Kerala's library
movement is thousands of grant-aided village libraries and reading rooms, plus
school/college libraries), and the biggest build: org accounts, roles, member
records, circulation, reports — it touches auth, RLS, and sync.

- **The wedge vs incumbents:** Koha is free but needs hosting and an IT person;
  NIC's e-Granthalaya serves government; SLIM/LIBSYS are dated desktop-era ₹
  products. A **hosted, mobile-first, zero-IT** circulation tool priced in
  hundreds-per-month — with a public shelf page per library that the web
  platform already knows how to render (a free OPAC, which none of the cheap
  options have) — is a real niche.
- **Pricing shape:** flat per-library per-year tiers by collection size
  (~₹2,500–10,000/yr), not per-seat — per-seat is sales friction at this price
  point. Note the overhead honestly: B2B means invoices, GST questions, and
  support expectations. That's a business decision to make *before* building.
- **Sequence — spend nothing until validated:**
  1. **Now (zero build):** a "Kitabi for libraries — join the pilot" line on the
     landing page with a contact link. Starts the funnel, measures pull.
  2. **Pilot:** 2–3 libraries, free, hands-on, to learn actual circulation
     workflows (member records, due/fine policy, reports they file).
  3. **Build only after pilots confirm** the workflows. Target: post-launch,
     months out.
- **Data-model prep:** almost none needed — lending is already a first-class
  record (rule 14) and the borrower is already free-text-or-user, which is
  exactly the shape a member ledger needs. Don't add `org_id` speculatively;
  record the concept in feature-map.md as `[LATER]` gated on the pilots.

### 3.5 Publisher accounts — **right idea, wrong order; start free**

Publishers pay for *reach*, and today there is none to sell. Charging DC Books
or Mathrubhumi a listing fee now would sour exactly the regional relationships
that matter most later. Flip it:

- **Now (cheap):** an "Are you the publisher?" claim link on `/p/` pages. The
  approval-queue pattern already exists (`author_claims`, migration `000029`) —
  publisher claims are the same shape. Verified publishers curate their own
  catalog entries **through the existing moderated-edit pipeline**
  (`work_revisions`) — free labour that improves the catalog, with no
  unreviewed writes (rule 18 stays intact).
- **Later (the paid product):** the promotions system built in Phase 9 *is* the
  publisher product — campaigns, language variants, audience targeting, results,
  all first-party with no ad SDK. "Announce your new release to Malayalam
  readers of this genre, in Malayalam" is a far better ROI story than a listing
  subscription, and per-campaign pricing beats a standing fee at this scale.
  Add reach analytics (how many readers shelved/rated your books) as the
  dashboard they renew for. Needs provable audience numbers first.
- **Never:** paid alteration of ratings, rankings, or catalog truth; unlabeled
  placement. Promotions stay visibly promotions.

---

## 4. Ideas beyond the five

- **Kindle/Audible/KU bounty links** — part of the affiliate block, flat-fee per
  signup, often better ₹ than book commissions.
- **Promoted placements as the general product** — publishers first; local
  bookstores and literary festivals are plausible later advertisers through the
  same first-party promotions system.
- **Deliberately not doing:**
  - **Display-ad SDKs** — pennies at this scale, wrecks the Reading Room feel and
    the no-ATT/no-ad-SDK stance Phase 9 was explicitly built around.
  - **Selling or licensing user/reading data** — never; it's the moat.
  - **Paywalling the wedge** (lending/library/sync/export) — see 3.2.
  - **Standalone donation flows in-app** — see 3.3.

---

## 5. Sequenced roadmap

**Now, pre-launch (days of work, all cheap):**
1. ~~Affiliate `buy_links` builder in the API + "Get this book" block on web book
   pages + app book-page row, server-served, with disclosure line.~~ **Built,
   8 Aug 2026** (`api/app/services/buy_links.py`; Amazon.in + Flipkart, tags via
   `AMAZON_ASSOCIATE_TAG`/`FLIPKART_AFFILIATE_ID`, dormant-untagged until set).
   *(Owner: Amazon Associates India signup, pick the tag, set it in Railway.)*
2. Landing page: "Kitabi for libraries — join the pilot" contact line.
3. `/p/` pages: publisher claim link (mailto/form → the claims queue pattern).
4. `profiles.premium_until` + `quota_for()` awareness — dormant plumbing.
5. Website-only support/UPI link (optional, an hour).

**Launch window:** ship the app; submit Search Console *(owner's Google
account — already on the task list)*; keep growing catalog depth (genres,
descriptions) — every affiliate rupee is downstream of that SEO work.

**Post-launch v1.x (1–2 weeks):** Supporter tier — StoreKit 2 + Play Billing +
server-side verification, Small Business Program, ₹99–199/yr annual SKU,
supporter badge. A/B Haiku 4.5 on cover-extract to cut the variable cost.

**Months out, gated on validation:** library pilots → build the B2B slice only
if 2–3 pilots convert to "we'd pay". Publisher promoted placements once
traffic/audience numbers are worth showing.

---

## 6. Owner-only actions (nothing here is buildable by the repo)

- Sign up **Amazon Associates India** (site: kitabi.in; choose tag, e.g.
  `kitabi0f-21`); note the 3-sales/180-days activation rule.
- **Search Console** submission (Google account) — precondition for the
  affiliate line mattering.
- Enroll the **Apple Small Business Program** before the Supporter tier ships.
- Decide the Supporter price point (recommendation: ₹149/yr) when the time comes.
- B2B prerequisites when pilots convert: invoicing/GST decision.
