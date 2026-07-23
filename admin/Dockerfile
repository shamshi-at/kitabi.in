# Kitabi Admin console. Reuses the API's `app` package (models, db, services),
# so this image bundles both and is built from the REPO ROOT, not admin/:
#
#     docker build -f admin/Dockerfile -t kitabi-admin .
#
# On Railway: a second service, Root Directory = repo root, Dockerfile path
# admin/Dockerfile. It talks to the same Supabase database as the API but runs
# its own process, so admin auth never shares memory with the reader API.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

# Install the API's deps (the admin imports its modules) plus the admin-only ones.
COPY api/requirements.txt ./api/requirements.txt
COPY admin/requirements.txt ./admin/requirements.txt
RUN pip install --no-cache-dir -r api/requirements.txt -r admin/requirements.txt

# The API package (imported via console/bootstrap.py's sys.path shim, which
# expects it at <repo>/api) and the console itself.
COPY api/app ./api/app
COPY admin/console ./admin/console
COPY admin/scripts ./admin/scripts

RUN useradd --create-home --uid 1000 admin
USER admin

EXPOSE 8100
# No migrations here — the API container owns Alembic. The admin only reads and
# writes rows the migration already created.
CMD ["sh", "-c", "uvicorn console.main:app --app-dir admin --host 0.0.0.0 --port ${PORT:-8100}"]
