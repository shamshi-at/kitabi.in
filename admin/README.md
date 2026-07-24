# admin/ — the Kitabi back office (admin.kitabi.in)

A server-rendered console (FastAPI + Jinja + a little htmx) for the people who
operate Kitabi: an insights dashboard, content moderation, catalog operations,
reader support, admin-user management, and an append-only audit log. Designed in
[docs/admin_mockups.html](../docs/admin_mockups.html) before a line was written.

**Admin identity is separate from reader identity.** Readers sign in with
Google/Apple through Supabase; an admin is a row in `admin_users` with an
Argon2id password and a TOTP secret, and there is no path from being a reader to
being an admin. Sessions are DB-backed (`admin_sessions`) with an opaque cookie
token, so no admin credential ever lives in JavaScript.

## Why it lives here but reuses the API

The console reuses the API's SQLAlchemy models, engine and services rather than
duplicating them — `console/bootstrap.py` adds `../api` to `sys.path` (the same
trick `etl/03_transform.py` uses), so `from app.models import …` resolves to the
API package. The admin package is named **`console`**, not `app`, precisely to
avoid colliding with the API's `app` package on that shared path.

The admin tables (`admin_users`, `admin_recovery_codes`, `admin_sessions`,
`admin_audit_log`, `content_reports`) are part of the one database schema, so
their migration lives with the rest in `api/alembic` (migration `000031`), RLS
enabled with zero policies like every other table.

## Run it locally

```bash
# 1. the admin tables must exist (once, against the dev DB on 55442)
cd api && DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:55442/kitabi" \
  .venv/bin/alembic upgrade head

# 2. create the founding super admin (prompts for a password)
cd ../admin && DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:55442/kitabi" \
  ../api/.venv/bin/python -m scripts.seed_super_admin --email at.shamshi@gmail.com

# 3. run the console (reuses api/.venv; needs jinja2 argon2-cffi pyotp segno python-multipart)
cd .. && api/.venv/bin/uvicorn console.main:app --app-dir admin --port 8100
```

Open <http://localhost:8100>. First sign-in forces TOTP enrolment: scan the QR,
save the recovery codes, confirm a code. After that: email + password + a
6-digit code each time.

The server reads `DATABASE_URL` through the API's own settings; with no env it
defaults to the local dev DB (port 55442), same as the API.

## Test

```bash
cd admin && ../api/.venv/bin/python -m pytest tests/ -q
```

The unit tests cover the auth primitives (Argon2 verify, TOTP, recovery codes,
the pending-2FA ticket, role ranking). The DB-backed flows — sign-in → TOTP →
session, claim approve/reject, admin management with its self-lockout guards —
are verified end-to-end against a running server and the dev database.

## Docker / deploy

Built from the **repo root** (it bundles `api/app`):

```bash
docker build -f admin/Dockerfile -t kitabi-admin .
```

On Railway this is a **second service** (Root Directory = repo root, Dockerfile
`admin/Dockerfile`) pointed at the same Supabase `DATABASE_URL`, with the
`admin.kitabi.in` domain in front. It runs no migrations — the API service owns
Alembic. `ENV=production` flips the session cookie to `Secure`.

## Email (Resend)

The sign-in flows (forgot-password OTP, magic link, invites) send email via
`console/mail.py`. With no transport configured they run **dormant** — the code/
link is written to the server log so the flows still work. To send for real:

1. **Resend → add domain** `kitabi.in` (or a subdomain like `mail.kitabi.in`).
   Resend shows SPF/DKIM (and DMARC) DNS records.
2. **Cloudflare → add those records** for `kitabi.in`, wait for Resend to verify.
3. **Resend → create an API key** (send-only).
4. **Railway (admin service) → set env vars:**
   ```
   RESEND_API_KEY=re_...            # the key — never commit it
   MAIL_FROM=Kitabi Admin <noreply@kitabi.in>   # a verified-domain sender
   ADMIN_BASE_URL=https://admin.kitabi.in       # so emailed links resolve
   ```
   That's it — the console prefers the Resend HTTP API when `RESEND_API_KEY` is
   set (no outbound-SMTP-port issues on Railway). SMTP is still supported as a
   fallback (`SMTP_HOST/PORT/USER/PASSWORD`) if you ever prefer it.

Keep **promotional** email on a *separate* provider and sending subdomain (e.g.
`news.kitabi.in`) so a marketing reputation hit can never affect these
transactional messages.

## What's built vs. planned

**Built and working:** the auth stack (password + forced TOTP + recovery codes +
DB sessions + lockout + audit); the email sign-in flows (forgot-password OTP,
passwordless magic link, email invites — via Resend, dormant until configured);
in-portal + forced password change; a global command-search (actions / books /
authors / publishers / readers); the dashboard; the three moderation queues
(author claims, suggested edits, reported content); catalog ops (search /
book·author·publisher pages / duplicate merge / quality gaps); reader support
(search / detail / suspend); admin-user management; and the audit log.

**Deferred:** promotional/marketing email (separate provider + consent, its own
project), and reader-facing report/notification triggers that would feed the
reported-content queue.
