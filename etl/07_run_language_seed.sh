#!/usr/bin/env bash
#
# 07_run_language_seed.sh — the per-language catalog seed job, end to end:
#
#   fetch top-100/language from the OpenLibrary API (07_language_seed.py)
#     → transform to Kitabi CSVs (03_transform.py: uuid5, translit/fold,
#       native script, publisher normalization)
#     → load into prod, idempotently (05_load_prod.sh / 04_load.sql)
#
#   ./07_run_language_seed.sh [workdir] [per-lang]
#
# Defaults: workdir ~/ol-dumps/langseed, 100 books per language, languages =
# the 13 Indic codes + India-focused English. Safe to re-run: fetches are
# disk-cached in workdir/cache, and the load only inserts works whose
# openlibrary external_id isn't already in the catalog — no duplicates.
# For a scripted run, export SEED_PROD_YES="SEED PROD" (05_load_prod.sh
# prompts for the phrase otherwise).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${1:-$HOME/ol-dumps/langseed}"
PER="${2:-100}"
PY="$HERE/../api/.venv/bin/python"

"$PY" "$HERE/07_language_seed.py" --out-dir "$WORK" --per-lang "$PER"
"$PY" "$HERE/03_transform.py" --in-dir "$WORK" --out-dir "$WORK/csv"
"$HERE/05_load_prod.sh" "$WORK/csv"
