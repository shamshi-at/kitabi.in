"""Seed (or reset) the founding super admin — the one admin that isn't created
by another admin. Run once against a database:

    cd admin
    ../api/.venv/bin/python -m scripts.seed_super_admin --email at.shamshi@gmail.com

Prompts for a password (or takes --password for non-interactive use), writes an
admin_users row with role super_admin and NO TOTP yet — the operator enrols an
authenticator on first sign-in at admin.kitabi.in/enrol. Re-running for an
existing email resets that admin's password and reactivates them (the recovery
path when a founder is locked out), but never touches their role or 2FA silently
without --force.

Targets the DB the API is configured for (api/.env). For prod, the same
Supavisor-pooler / no-IPv6 rules apply as everywhere else.
"""

import argparse
import asyncio
import getpass
import os
import sys
from pathlib import Path

# Target the API's configured database regardless of where this is run from.
# The API's settings resolve `.env` relative to the CWD, so running this script
# from admin/ found no .env and silently fell back to the localhost dev default
# — seeding the wrong database (bit us seeding the prod founder, 24 Jul 2026).
# Load api/.env by ABSOLUTE path into the environment BEFORE app.core.db is
# imported (its engine is built from the settings at import time). An already-set
# DATABASE_URL (e.g. injected on Railway) always wins.
_API_ENV = Path(__file__).resolve().parents[2] / "api" / ".env"
if not os.environ.get("DATABASE_URL") and _API_ENV.exists():
    for _line in _API_ENV.read_text().splitlines():
        if _line.startswith("DATABASE_URL="):
            os.environ["DATABASE_URL"] = _line.split("=", 1)[1].strip().strip("\"'")
            break

# Make the admin package (console) — and through it the API package —
# importable. `console.models_ref` runs the sys.path shim that adds api/ so
# `app.*` resolves to the API package.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # admin/
from sqlalchemy import select  # noqa: E402

from console import config, security  # noqa: E402
from console.models_ref import ROLE_SUPER_ADMIN, AdminUser, SessionLocal  # noqa: E402


async def _run(email: str, password: str, force: bool) -> None:
    email = email.strip().lower()
    async with SessionLocal() as db:
        existing = (
            await db.execute(select(AdminUser).where(AdminUser.email == email))
        ).scalar_one_or_none()
        if existing is not None:
            if not force:
                print(f"{email} already exists — resetting password and reactivating.")
            existing.password_hash = security.hash_password(password)
            existing.is_active = True
            existing.failed_attempts = 0
            existing.locked_until = None
            if force:
                existing.role = ROLE_SUPER_ADMIN
            await db.commit()
            await security.audit(
                db,
                "admin.seed_reset",
                admin_id=existing.id,
                target_type="admin",
                target_id=str(existing.id),
                summary=email,
            )
            print(f"✓ Reset super admin {email}. Sign in and enrol TOTP at /enrol.")
            return
        admin = AdminUser(
            email=email,
            password_hash=security.hash_password(password),
            role=ROLE_SUPER_ADMIN,
            is_active=True,
        )
        db.add(admin)
        await db.commit()
        await security.audit(
            db,
            "admin.seed_create",
            admin_id=admin.id,
            target_type="admin",
            target_id=str(admin.id),
            summary=email,
        )
        print(f"✓ Created super admin {email}. Sign in and enrol TOTP at /enrol.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--email", required=True)
    ap.add_argument("--password", help="if omitted, prompts (twice)")
    ap.add_argument("--force", action="store_true", help="also reset role to super_admin")
    args = ap.parse_args()

    # Show which database we're about to write to (host only, no credentials),
    # so seeding the wrong DB is caught before a password is even typed.
    import re

    host = re.sub(r"://[^@]*@", "://", os.environ.get("DATABASE_URL", "localhost-default"))
    print(f"Target database: {host}")

    minlen = config.MIN_PASSWORD_LENGTH
    password = args.password
    if not password:
        password = getpass.getpass(f"Password (min {minlen} chars): ")
        if password != getpass.getpass("Confirm password: "):
            raise SystemExit("Passwords did not match.")
    # Enforce the minimum on both paths (interactive and --password).
    if len(password) < minlen:
        raise SystemExit(f"Password must be at least {minlen} characters.")

    asyncio.run(_run(args.email, password, args.force))


if __name__ == "__main__":
    main()
