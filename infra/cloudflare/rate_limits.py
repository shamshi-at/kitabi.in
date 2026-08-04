#!/usr/bin/env python3
"""Apply Kitabi's Cloudflare rate limiting rule to the kitabi.in zone.

The rules live here as code rather than as invisible dashboard state — DNS is
already "configure it in the dashboard and hope you remember", and that is
exactly the kind of ops knowledge that evaporates. Re-running this is safe: it
replaces the http_ratelimit entrypoint with what's defined below, and refuses
to clobber rules it didn't write unless you pass --force.

Usage
-----
    export CLOUDFLARE_API_TOKEN=...      # a token scoped to this zone, see README
    ./rate_limits.py                     # DRY RUN — prints the diff, changes nothing
    ./rate_limits.py --apply             # actually write it
    ./rate_limits.py --apply --force     # …and drop unmanaged rules that are there

Needs a token with **Zone → WAF → Edit** (plus Zone → Zone → Read to resolve the
zone id). The Pages deploy token in GitHub Actions does NOT have this and must
not be reused — mint a separate one, scoped to the kitabi.in zone only.

Standard library only: this must run on any machine with python3 and no venv.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.cloudflare.com/client/v4"
ZONE_NAME = "kitabi.in"

# Every rule this script owns is tagged with this prefix in its description, so
# a re-run can tell "mine, replace it" from "someone added this in the
# dashboard, don't silently delete it".
TAG = "[kitabi-managed]"

# --------------------------------------------------------------------------
# The rule
# --------------------------------------------------------------------------
#
# ONE rule, because the Cloudflare free plan allows exactly one rate limiting
# rule. Chosen for what nothing else protects:
#
#   * Anthropic spend is already capped hard and precisely by the per-reader
#     quota + global circuit breaker in the API (services/llm_quota.py), so an
#     edge rule adds little there.
#   * Catalogue scraping is low-harm by design — the whole SEO plan wants this
#     content crawled (docs/web-platform-plan.md §11).
#   * What has NO protection is a single IP hammering the API into a real
#     outage. The pool is pool_size=10 + max_overflow=10 (api/app/core/db.py);
#     saturate that and every legitimate reader gets errors. That is an
#     availability risk, and it's what this rule is for.
#
# Threshold: 50 requests per 10s per IP ≈ 5 req/s sustained. A real app session
# (a sync push/pull plus a few catalog GETs, search debounced at 300ms) never
# comes close; anything that does is not a person reading a book.
#
# ACTION IS `block`, DELIBERATELY NOT A CHALLENGE. api.kitabi.in serves the
# Flutter app and the edge functions — neither can solve a managed challenge, so
# challenging them is indistinguishable from breaking them.
#
# `not cf.client.bot` exempts VERIFIED bots (Googlebot, Bingbot, …). This is
# load-bearing: the entire web platform plan depends on those crawlers being
# able to walk 1,400+ pages without ever being throttled.
RULES = [
    {
        "description": f"{TAG} API burst shield — per-IP ceiling on api.kitabi.in, verified bots exempt",
        # http.host keeps this off the landing page and its share pages, which
        # live in the same zone. If your plan rejects http.host in a rate
        # limiting expression, use the path-only fallback in README.md.
        "expression": (
            '(http.host eq "api.kitabi.in") '
            "and (not cf.client.bot)"
        ),
        "action": "block",
        "ratelimit": {
            # Non-Enterprise plans require exactly these two characteristics.
            "characteristics": ["ip.src", "cf.colo.id"],
            "period": 10,
            "requests_per_period": 50,
            "mitigation_timeout": 10,
        },
    }
]


def _req(path: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{API}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        # Never echo the token; the body may name the permission that's missing,
        # which is the single most useful thing when this fails.
        sys.exit(f"Cloudflare API {err.code} on {method} {path}:\n{detail}")
    except urllib.error.URLError as err:
        sys.exit(f"Could not reach the Cloudflare API: {err.reason}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="write the change (default: dry run)")
    ap.add_argument(
        "--force",
        action="store_true",
        help="replace rules this script did not create instead of refusing",
    )
    args = ap.parse_args()

    token = os.environ.get("CLOUDFLARE_API_TOKEN")
    if not token:
        sys.exit(
            "CLOUDFLARE_API_TOKEN is not set.\n"
            "Mint one at https://dash.cloudflare.com/profile/api-tokens with\n"
            "  Zone → WAF → Edit  and  Zone → Zone → Read,  scoped to kitabi.in.\n"
            "Do NOT reuse the Pages deploy token from GitHub Actions."
        )

    zones = _req(f"/zones?name={ZONE_NAME}", token)["result"]
    if not zones:
        sys.exit(f"No zone named {ZONE_NAME} is visible to this token.")
    zone = zones[0]
    zone_id, plan = zone["id"], zone.get("plan", {}).get("name", "unknown")
    print(f"zone            : {ZONE_NAME} ({zone_id[:8]}…)")
    print(f"plan            : {plan}")

    allowed = {"Free Website": 1, "Pro Website": 2, "Business Website": 5}.get(plan)
    if allowed is not None:
        print(f"rules allowed   : {allowed}")
        if len(RULES) > allowed:
            sys.exit(f"This script defines {len(RULES)} rules but the {plan} plan allows {allowed}.")

    entry = _req(f"/zones/{zone_id}/rulesets/phases/http_ratelimit/entrypoint", token)["result"]
    existing = entry.get("rules") or []
    unmanaged = [r for r in existing if TAG not in (r.get("description") or "")]

    print(f"\nexisting rules  : {len(existing)} ({len(unmanaged)} not managed by this script)")
    for r in existing:
        owner = "managed" if TAG in (r.get("description") or "") else "UNMANAGED"
        print(f"  - [{owner}] {r.get('description') or '(no description)'}")

    if unmanaged and not args.force:
        sys.exit(
            "\nRefusing to continue: the rules above were not created by this script and\n"
            "writing the entrypoint would delete them. Re-run with --force if that's what\n"
            "you want, or fold them into RULES first."
        )

    print("\nwill apply:")
    for r in RULES:
        rl = r["ratelimit"]
        print(f"  - {r['description']}")
        print(f"      expression : {r['expression']}")
        print(
            f"      limit      : {rl['requests_per_period']} req / {rl['period']}s per "
            f"{'+'.join(rl['characteristics'])} → {r['action']} for {rl['mitigation_timeout']}s"
        )

    if not args.apply:
        print("\nDRY RUN — nothing was changed. Re-run with --apply to write it.")
        return

    _req(
        f"/zones/{zone_id}/rulesets/phases/http_ratelimit/entrypoint",
        token,
        method="PUT",
        body={"rules": RULES},
    )
    print("\n✅ applied.")
    print("Verify with a burst against a cheap endpoint, e.g.:")
    print("  for i in $(seq 1 80); do curl -s -o /dev/null -w '%{http_code} ' \\")
    print("    https://api.kitabi.in/healthz; done; echo")
    print("…expect 200s to turn into 429/403 partway through, then recover within ~10s.")


if __name__ == "__main__":
    main()
