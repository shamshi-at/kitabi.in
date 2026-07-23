#!/usr/bin/env bash
#
# 05_load_prod.sh — run 04_load.sql against the PRODUCTION Supabase catalog.
#
#     ./05_load_prod.sh ~/ol-dumps/maltest/csv
#
# The load itself is the same idempotent transaction used locally: it only
# inserts rows whose openlibrary external_id isn't already present, so a
# re-run converges instead of duplicating. This wrapper adds the things you
# want when the target is production and there's no psql on the host:
#
#   - reads DATABASE_URL from api/.env and converts SQLAlchemy's
#     postgresql+asyncpg:// form to the plain URL psql needs
#   - refuses anything but the Supavisor pooler (port 6543): the direct
#     db.<ref>.supabase.co:5432 host resolves IPv6-only and hangs on most
#     networks (CLAUDE.md, "things that have bitten us")
#   - prints prod row counts before and after, and the CSV sizes going in
#   - requires you to type the confirmation phrase
#
# psql runs in a throwaway postgres:17-alpine container with the CSV dir
# mounted, so nothing is installed on the host and the dev-DB container is
# left alone.
#
# To undo a seed: every row it writes carries external_source='openlibrary',
# so DELETE ... WHERE external_source='openlibrary' (children first:
# work_authors, editions, then works/authors/publishers) reverses it.

set -euo pipefail

CSV_DIR="${1:-}"
if [[ -z "$CSV_DIR" || ! -d "$CSV_DIR" ]]; then
    echo "usage: $0 <csv-dir>   (the --out-dir of 03_transform.py)" >&2
    exit 1
fi
CSV_DIR="$(cd "$CSV_DIR" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/../api/.env"
[[ -f "$ENV_FILE" ]] || { echo "no $ENV_FILE — cannot resolve the prod URL" >&2; exit 1; }

for f in works.csv authors.csv publishers.csv editions.csv work_authors.csv; do
    [[ -f "$CSV_DIR/$f" ]] || { echo "missing $CSV_DIR/$f — run 03_transform.py first" >&2; exit 1; }
done

# postgresql+asyncpg://... -> postgresql://...  (psql doesn't know the driver suffix)
# \042 = double quote, \047 = single quote — strip either if .env wraps the value.
URL="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '\042\047' | sed 's|+asyncpg||')"
[[ -n "$URL" ]] || { echo "DATABASE_URL not found in $ENV_FILE" >&2; exit 1; }

case "$URL" in
    *localhost*|*127.0.0.1*)
        echo "DATABASE_URL points at localhost — this script is for prod." >&2
        echo "For a local load see the README's docker exec recipe." >&2
        exit 1 ;;
    *:6543/*) ;;  # Supavisor transaction pooler — the only supported target
    *)  echo "Refusing: DATABASE_URL is not the Supavisor pooler (port 6543)." >&2
        echo "The direct 5432 host is IPv6-only and will hang. Fix api/.env." >&2
        exit 1 ;;
esac

HOST="$(echo "$URL" | sed -E 's|.*@([^:/]+).*|\1|')"

echo "── target ─────────────────────────────────────────────"
echo "  host : $HOST (pooler)"
echo "  csv  : $CSV_DIR"
for f in works authors publishers editions work_authors; do
    printf "         %-13s %s rows\n" "$f" "$(($(wc -l < "$CSV_DIR/$f.csv") - 1))"
done

psql_prod() {
    docker run --rm -i \
        -v "$CSV_DIR":/csv \
        -v "$HERE/04_load.sql":/sql/04_load.sql:ro \
        -w /csv postgres:17-alpine \
        psql "$URL" "$@"
}

echo "── prod catalog before ────────────────────────────────"
psql_prod -tA -c "select 'works='||(select count(*) from works)
                       ||' editions='||(select count(*) from editions)
                       ||' authors='||(select count(*) from authors)
                       ||' publishers='||(select count(*) from publishers);"

echo
echo "This INSERTS into the production catalog. Existing rows are left alone"
echo "(matched by openlibrary external_id), and the whole load is one"
echo "transaction — but it is still production."
# Non-interactive path for scripted runs. Deliberately requires the same exact
# phrase, so it can't be satisfied by a stray truthy value; piping the phrase
# into the prompt instead is NOT viable — the docker runs above attach stdin.
if [[ "${SEED_PROD_YES:-}" == "SEED PROD" ]]; then
    echo 'confirmed via SEED_PROD_YES'
else
    read -r -p 'Type "SEED PROD" to continue: ' reply
    [[ "$reply" == "SEED PROD" ]] || { echo "aborted."; exit 1; }
fi

psql_prod -v ON_ERROR_STOP=1 -f /sql/04_load.sql

echo "── prod catalog after ─────────────────────────────────"
psql_prod -tA -c "select 'works='||(select count(*) from works)
                       ||' editions='||(select count(*) from editions)
                       ||' authors='||(select count(*) from authors)
                       ||' publishers='||(select count(*) from publishers);"

echo
echo "Fresh stats for the trigram indexes (search quality depends on these):"
psql_prod -c "ANALYZE works; ANALYZE editions; ANALYZE authors; ANALYZE publishers;"
echo "done."
