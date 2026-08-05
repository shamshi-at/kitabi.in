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

# Railway injects PORT; default to 8000 locally.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
