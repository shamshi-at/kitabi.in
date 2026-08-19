#!/usr/bin/env python3
"""Check every editorial list against the live catalogue.

The first draft of `_lib/lists.js` was curated against books that *ought* to be
in the catalogue rather than books that *are* — chemmeen, balyakalasakhi,
khasakkinte-ithihasam. Every entry was silently skipped and the page rendered as
a title and an intro over nothing. Nothing failed; the renderer suite stayed
green, because the bug was in the content, not the code.

So this is the guard. It is deliberately NOT part of `run.py`: it needs the
network and the live API, and a deploy should not fail because Railway was
briefly slow. Run it after editing a list.

    ./landing-page/tests/check_lists.py

Exits non-zero if any list would fail to render (fewer than MIN_ENTRIES of its
books resolve), and warns about individual dead slugs either way.
"""

import json
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

API = "https://api.kitabi.in"
LISTS_JS = Path(__file__).resolve().parents[1] / "functions" / "_lib" / "lists.js"

# Must match MIN_LIST_ENTRIES in functions/_lib/handler.js — below this a list
# 404s rather than publishing a hollow page.
MIN_ENTRIES = 3

# A list's own slug is the one immediately followed by `title:`; entry slugs are
# everything inside that list's `entries: [ … ]`. Keyed off structure rather than
# indentation — the first version of this matched on a fixed indent, silently
# found zero entries, and reported every list as failing for the wrong reason.
LIST_HEAD_RE = re.compile(r"slug:\s*'([^']+)',\s*\n\s*title:")
SLUG_RE = re.compile(r"slug:\s*'([^']+)'")


def parse_lists() -> list[tuple[str, list[str]]]:
    """Pull (list slug, [entry slugs]) out of the JS without a JS parser."""
    text = LISTS_JS.read_text()
    heads = list(LIST_HEAD_RE.finditer(text))
    out: list[tuple[str, list[str]]] = []
    for i, head in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        block = text[head.end() : end]
        entries_at = block.find("entries:")
        if entries_at == -1:
            continue
        out.append((head.group(1), SLUG_RE.findall(block[entries_at:])))
    return out


def resolve(slugs: list[str]) -> set[str]:
    if not slugs:
        return set()
    query = urllib.parse.urlencode([("slug", s) for s in slugs])
    # curl rather than urllib: the API sits behind Cloudflare, which 403s
    # urllib's default user agent.
    proc = subprocess.run(
        ["curl", "-sS", "-m", "40", f"{API}/public/works?{query}"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"Could not reach the API: {proc.stderr.strip()}")
    try:
        return {w["slug"] for w in json.loads(proc.stdout) if w.get("slug")}
    except json.JSONDecodeError:
        sys.exit(f"Unexpected API response:\n{proc.stdout[:400]}")


def main() -> int:
    lists = parse_lists()
    if not lists:
        sys.exit(
            "Parsed no lists out of lists.js — the format changed; fix this script."
        )

    every = sorted({s for _, entries in lists for s in entries})
    live = resolve(every)

    failed = False
    for list_slug, entries in lists:
        found = [s for s in entries if s in live]
        missing = [s for s in entries if s not in live]
        ok = len(found) >= MIN_ENTRIES
        mark = "ok  " if ok else "FAIL"
        print(
            f"  {mark} /list/{list_slug}  —  {len(found)}/{len(entries)} books in the catalogue"
        )
        for slug in missing:
            print(f"         missing: {slug}")
        if not ok:
            failed = True

    print(f"\n{len(live)}/{len(every)} distinct slugs resolve")
    if failed:
        print("At least one list would 404. Curate against books that exist.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
