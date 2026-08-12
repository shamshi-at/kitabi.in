"""Delete Supabase Auth accounts — the second half of the pre-launch wipe.

`scripts/reset_user_data.py` clears everything in the `public` schema, but the
accounts themselves live in `auth.users`, which the application's database role
cannot touch (that schema belongs to `supabase_auth_admin`). They go through the
Auth Admin API instead, which also cleans up the identities, sessions and
refresh tokens that hang off each account — a raw DELETE would not.

Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. The service-role key is a full
bypass of RLS and every auth rule; it lives on Railway, never in the repo.

    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
        .venv/bin/python scripts/delete_auth_users.py                  # list only

    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
        .venv/bin/python scripts/delete_auth_users.py --apply --confirm-project <ref>

`--confirm-project` must match the project ref in SUPABASE_URL, so the one thing
you type by hand is the thing that identifies the project being emptied.

`--keep me@example.com` (repeatable) spares an account — useful to keep your own
sign-in working while clearing everyone else. Note that sparing an account here
after running the data wipe leaves it signing in to an empty library, which is
what a returning reader would see anyway.
"""

from __future__ import annotations

import argparse
import os
import sys
from urllib.parse import urlsplit

import httpx

PAGE = 200


def project_ref(url: str) -> str:
    host = urlsplit(url).hostname or ""
    return host.split(".")[0] if host.endswith(".supabase.co") else host


def list_users(client: httpx.Client, base: str) -> list[dict]:
    users: list[dict] = []
    page = 1
    while True:
        r = client.get(f"{base}/auth/v1/admin/users", params={"page": page, "per_page": PAGE})
        r.raise_for_status()
        batch = r.json().get("users", [])
        users += batch
        if len(batch) < PAGE:
            return users
        page += 1


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apply", action="store_true", help="actually delete (default: list only)")
    p.add_argument("--confirm-project", default="", help="must match the ref in SUPABASE_URL")
    p.add_argument(
        "--keep", action="append", default=[], metavar="EMAIL", help="spare this account"
    )
    args = p.parse_args()

    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not base or not key:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must both be set.", file=sys.stderr)
        return 2

    ref = project_ref(base)
    keep = {e.strip().lower() for e in args.keep}
    print(f"project : {ref}")
    print(f"mode    : {'APPLY — deletes accounts' if args.apply else 'list only'}\n")

    with httpx.Client(
        timeout=30,
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    ) as client:
        users = list_users(client, base)
        doomed = [u for u in users if (u.get("email") or "").lower() not in keep]
        spared = [u for u in users if u not in doomed]

        for u in users:
            mark = "keep  " if u in spared else "DELETE"
            print(f"  {mark}  {u['id']}  {u.get('email') or '(no email)'}  {u.get('created_at')}")
        print(f"\n  {len(doomed)} to delete, {len(spared)} kept")

        if not args.apply:
            print("\nList only — nothing was changed.")
            return 0
        if args.confirm_project.strip() != ref:
            print(
                f"\nRefusing to run: --confirm-project {args.confirm_project!r} != {ref!r}.",
                file=sys.stderr,
            )
            return 2

        failed = []
        for u in doomed:
            r = client.delete(f"{base}/auth/v1/admin/users/{u['id']}")
            ok = r.status_code in (200, 204)
            print(f"  {'deleted' if ok else f'FAILED {r.status_code}'}  {u.get('email')}")
            if not ok:
                failed.append((u.get("email"), r.status_code, r.text[:200]))

        remaining = list_users(client, base)
        print(f"\nverification: {len(remaining)} account(s) remain")
        for u in remaining:
            print(f"  {u['id']}  {u.get('email')}")
        if failed:
            print(f"\n{len(failed)} deletion(s) failed: {failed}", file=sys.stderr)
            return 1
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
