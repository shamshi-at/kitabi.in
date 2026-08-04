# Cloudflare rules for the kitabi.in zone

Edge protection for `api.kitabi.in`, kept as code rather than as dashboard state
nobody can review. Part of the API-hardening track —
[docs/web-platform-plan.md](../../docs/web-platform-plan.md) §11, Phase S in
[docs/tasks.md](../../docs/tasks.md).

```bash
export CLOUDFLARE_API_TOKEN=...    # see "The token" below
./rate_limits.py                   # dry run — prints the diff, changes nothing
./rate_limits.py --apply           # write it
```

---

## What this protects, and what it doesn't

The honest framing first, because the free plan is more limited than it looks.

**The free plan allows exactly one rate limiting rule**, counting by IP, over a
short window with a short mitigation timeout. That makes this a **burst shield,
not an anti-scraping control.** Someone who paces a scraper below the threshold
walks straight through it, and no free-plan rule will stop them.

That is an acceptable outcome here, and deliberately so:

| Risk | What actually bounds it |
|---|---|
| **Anthropic spend** | The per-reader daily quota + global circuit breaker in the API (`api/app/services/llm_quota.py`). Precise, per-user, and independent of the edge — this rule is not what protects the bill |
| **Catalogue scraping** | Nothing, on purpose. The whole web platform plan wants this content crawled; the data is public by design and its value is in the pages, not in secrecy |
| **A single IP hammering the API into an outage** | **This rule.** The DB pool is `pool_size=10 + max_overflow=10` (`api/app/core/db.py`) — saturate it and every real reader gets errors |

So the one rule we get is spent on **availability**, because that is the only
one of the three with no other defence.

## The rule

| | |
|---|---|
| Match | `http.host eq "api.kitabi.in"` and **not** a verified bot |
| Count | per IP (+ Cloudflare colo, required on non-Enterprise plans) |
| Limit | 50 requests / 10 s ≈ 5 req/s sustained |
| Action | **block**, briefly |

**Why `block` and not a challenge.** `api.kitabi.in` serves the Flutter app and
the edge functions. Neither can solve a managed challenge, so challenging them
is indistinguishable from breaking them. Never put an interactive challenge in
front of an API.

**Why verified bots are exempt.** Googlebot and friends must be able to walk
1,400+ catalogue pages without ever being throttled — the entire SEO plan
depends on it. `not cf.client.bot` matches *verified* bots only (Cloudflare
validates them by reverse DNS/ASN), so it isn't a user-agent string anyone can
claim.

**Why 50/10s.** A real session is a sync push/pull plus a handful of catalog
GETs, with search debounced at 300 ms. Nothing a person does approaches 5 req/s.

### If `http.host` is rejected on your plan

Free-plan rate limiting expressions support a reduced field set. If the API
refuses `http.host`, fall back to matching the API's paths — they don't collide
with the landing page's (`/b/`, `/a/`, `/p/`, `/sitemaps/`):

```
(starts_with(http.request.uri.path, "/catalog/")
 or starts_with(http.request.uri.path, "/sync/")
 or starts_with(http.request.uri.path, "/recommendations")
 or starts_with(http.request.uri.path, "/users/")
 or starts_with(http.request.uri.path, "/me"))
and (not cf.client.bot)
```

## ⚠️ Before the public web is edge-rendered (W1)

Today the browser calls `api.kitabi.in` directly, so "per IP" means per reader
and this rule is safe.

**After W1 it will not be.** Every page render becomes a Pages Function calling
the API server-side, so a large share of API traffic stops being "one IP per
reader" and starts being "the edge". A per-IP ceiling can then throttle
*Cloudflare itself* and take the whole public site down under exactly the
traffic spike it's supposed to survive.

Before W1 ships, this rule must gain an exemption for the edge — which is what
the **edge→origin shared secret** item in Phase S is for. A `skip` custom rule
matching that header, ordered ahead of this one, is the fix. Do not ship edge
SSR and leave this rule as-is.

## The token

Mint a **new** token at <https://dash.cloudflare.com/profile/api-tokens>:

- **Zone → WAF → Edit** (create the rule)
- **Zone → Zone → Read** (resolve the zone id)
- **Zone Resources → Include → Specific zone → kitabi.in**

**Do not reuse `CLOUDFLARE_API_TOKEN` from GitHub Actions.** That one is scoped
to *Cloudflare Pages: Edit* for the landing-page deploy and has no zone/WAF
permission — and widening it would give the deploy workflow the ability to
rewrite your firewall.

Keep this token out of the repo and out of `api/.env`. Export it for the one
command and let it go; it is not needed at runtime by anything.

## Doing it in the dashboard instead

Security → WAF → **Rate limiting rules** → *Create rule*:

1. **Name** — `API burst shield`
2. **If incoming requests match** — Field `Hostname`, Operator `equals`, Value
   `api.kitabi.in`. Add `And`, Field `Verified Bot`, Operator `equals`, Value
   `Off`.
3. **With the same characteristics** — `IP`
4. **When rate exceeds** — `50` requests per `10` seconds
5. **Then take action** — `Block`, for the shortest available duration
6. Deploy.

The script is preferred — it is reviewable, re-runnable, and leaves the rule
written down somewhere other than one person's memory.

## Verifying it works

```bash
for i in $(seq 1 80); do curl -s -o /dev/null -w '%{http_code} ' https://api.kitabi.in/healthz; done; echo
```

Expect 200s to become 429/403 partway through, then recover within seconds.
Run it once, deliberately — you are rate-limiting your own IP against your own
production API, and the app on your phone shares that IP.

## The other four free rules

The free plan also includes **5 WAF custom rules**, which match but cannot
count — no rate component, so they can't do this job. Nothing is worth spending
them on today; the obvious candidates (blocking `/wp-admin`, `/.env`, `/.git`
probes) are noise the API already 404s cheaply. The first genuine use will be
the `skip` rule for the edge secret described above.
