#!/usr/bin/env bash
# `flutter run` with every --dart-define the app needs, read from
# dart_defines.env (gitignored — see dart_defines.env.example and
# build_ipa.sh for why this exists).
#
# POSIX-ish on purpose (no associative arrays) — macOS ships Bash 3.2,
# which predates `declare -A`.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="dart_defines.env"
REQUIRED_KEYS="API_BASE_URL SUPABASE_URL SUPABASE_PUBLISHABLE_KEY"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found." >&2
  echo "Copy dart_defines.env.example to dart_defines.env and fill in real values." >&2
  exit 1
fi

define_args=()
for key in $REQUIRED_KEYS; do
  value="$(grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d'=' -f2-)"
  if [[ -z "$value" ]]; then
    echo "error: $key is missing or empty in $ENV_FILE." >&2
    exit 1
  fi
  define_args+=(--dart-define="${key}=${value}")
done

flutter run "${define_args[@]}" "$@"
