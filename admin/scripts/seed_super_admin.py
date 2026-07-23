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
import sys
from pathlib import Path

# Make both the admin package (console) and, through its bootstrap, the API
# package importable. `console.models_ref` runs the sys.path shim that adds
# api/ so `app.*` resolves to the API package.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # admin/
from console import security  # noqa: E402
from console.models_ref import ROLE_SUPER_ADMIN, AdminUser, SessionLocal  # noqa: E402

from sqlalchemy import select  # noqa: E402


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
    ap.add_argument(
        "--force", action="store_true", help="also reset role to super_admin"
    )
    args = ap.parse_args()

    password = args.password
    if not password:
        password = getpass.getpass("Password (min 12 chars): ")
        if len(password) < 12:
            raise SystemExit("Password must be at least 12 characters.")
        if password != getpass.getpass("Confirm password: "):
            raise SystemExit("Passwords did not match.")

    asyncio.run(_run(args.email, password, args.force))


if __name__ == "__main__":
    main()
