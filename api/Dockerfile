# Must always build — this is the escape hatch from Railway (CLAUDE.md rule 9).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY alembic ./alembic
COPY alembic.ini .

# Non-root
RUN useradd --create-home --uid 1000 api
USER api

EXPOSE 8000

# Migrating the real database on boot is this container's job, so it opts past
# the guard in alembic/env.py (which otherwise refuses a non-local host — see
# the note there). Declared HERE, in the repo, rather than as a Railway
# dashboard variable, so the one place production is allowed to migrate is
# readable from a git checkout. tests/test_migration_guard.py asserts this line
# still exists: removing it would restart-loop production at the next deploy.
ENV ALLOW_PROD_MIGRATION=1

# Announce newly-indexable book pages to IndexNow (Bing/Yandex/Seznam/Naver).
# Set here rather than in the Railway dashboard for the same reason as above:
# the deployed behaviour should be readable from a git checkout. Off everywhere
# else, so a laptop never announces pages. See app/services/indexnow.py.
ENV INDEXNOW_ENABLED=1

# Daily catalogue intake (docs/catalog-intake-plan.md): ON, by owner decision,
# 4 Oct 2026. Every night at 02:30 IST (21:00 UTC; `catalog_intake_run_hour_utc`)
# the job stages what OpenLibrary and the
# publishers' storefronts list, and publishes up to
# `catalog_intake_daily_limit` complete books as public pages — unattended.
#
# Declared here rather than in the Railway dashboard for the same reason as
# the two above: the deployed behaviour should be readable from a git checkout.
# To stop it, delete this line and push — the job goes dormant and nothing it
# published is touched. To undo a night, api/scripts/revert_intake.py.
ENV CATALOG_INTAKE_ENABLED=1

# Kerala Book Store (services/intake_keralabookstore.py): read this many of its
# newest not-yet-staged pages each night — ON at 150, by owner decision,
# 6 Oct 2026. Ten seconds a page (the shop's own stated crawl delay), so about
# twenty-five minutes added to the night; staged every 25 pages, so a deploy in
# the middle loses a batch rather than the night. Setting this is also the
# decision that a retailer's covers are copied to our bucket as a publisher's
# own are (docs/catalog-intake-plan.md section 4). To stop it, delete this line
# (or set it to 0) and push; nothing it staged or published is touched.
ENV CATALOG_INTAKE_KERALABOOKSTORE_PAGES=150

# Railway injects PORT; default to 8000 locally.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
