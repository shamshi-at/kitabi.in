#!/usr/bin/env bash
# On-demand plaintext pg_dump to a local file — the manual counterpart to
# .github/workflows/backup.yml (which encrypts to R2 and needs its secrets set).
# Use it before anything irreversible: a migration you are unsure of, or the
# pre-launch wipe in scripts/reset_user_data.py.
#
#   DATABASE_URL=... ./scripts/dump_db.sh /path/to/out-dir
#
# DATABASE_URL may be the transaction-pooler URL the app uses (port 6543, and
# possibly postgresql+asyncpg://) — pg_dump cannot speak to either, so both are
# rewritten here: the driver suffix is dropped and 6543 becomes 5432, Supavisor's
# SESSION-mode port. pg_dump runs in a container so the client version matches
# the Supabase server without installing Postgres locally.
#
# The output is UNENCRYPTED and contains everything. Keep it off shared disks and
# delete it once the change it was insurance for has settled.
set -euo pipefail

OUT_DIR="${1:-.}"

# Fall back to api/.env, the same file the dev server reads, so the connection
# string never has to be typed on a command line or left in shell history.
if [ -z "${DATABASE_URL:-}" ] && [ -f "$(dirname "$0")/../.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$(dirname "$0")/../.env"
  set +a
fi
: "${DATABASE_URL:?DATABASE_URL is not set (and api/.env has none)}"

DUMP_URL="${DATABASE_URL/+asyncpg/}"
DUMP_URL="${DUMP_URL/:6543/:5432}"

HOST="$(printf '%s' "$DUMP_URL" | sed -E 's#.*@([^:/]+).*#\1#')"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILE="${OUT_DIR%/}/kitabi-${STAMP}.sql.gz"

mkdir -p "$OUT_DIR"
echo "dumping ${HOST} -> ${FILE}"

# The URL goes in via PGDATABASE, not argv: libpq expands a `dbname` that looks
# like a connection URI, and this keeps the password out of `docker ps` output.
docker run --rm -e PGCONNECT_TIMEOUT=30 -e PGDATABASE="$DUMP_URL" postgres:17-alpine \
  pg_dump --no-owner --no-privileges | gzip -9 >"$FILE"

SIZE="$(du -h "$FILE" | cut -f1)"
LINES="$(gzip -dc "$FILE" | wc -l | tr -d ' ')"
echo "wrote ${FILE} (${SIZE}, ${LINES} lines)"
gzip -t "$FILE" && echo "gzip integrity OK"
