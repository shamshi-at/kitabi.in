#!/usr/bin/env bash
# Builds a release IPA with every --dart-define the app needs, read from
# dart_defines.env (gitignored — see dart_defines.env.example).
#
# Why this script exists: every --dart-define must be passed explicitly on
# every single `flutter build` invocation — none of them carry over between
# builds. Passing them by hand is exactly how SUPABASE_URL/
# SUPABASE_PUBLISHABLE_KEY got silently dropped for three IPA builds in a
# row (the app fell back to an "unconfigured" stub auth service that always
# fails sign-in, with no build-time error). This script is the fix: it's
# the one place all required defines are listed, so a build either has all
# of them or fails loudly before Xcode even starts.
#
# POSIX-ish on purpose (no associative arrays) — macOS ships Bash 3.2,
# which predates `declare -A`.
set -euo pipefail
cd "$(dirname "$0")/.."

# Locate flutter — on PATH if set up, else the known SDK location (CLAUDE.md:
# SDK at ~/development/flutter, not on the default PATH).
FLUTTER="$(command -v flutter || true)"
if [[ -z "$FLUTTER" && -x "$HOME/development/flutter/bin/flutter" ]]; then
  FLUTTER="$HOME/development/flutter/bin/flutter"
fi
if [[ -z "$FLUTTER" ]]; then
  echo "error: flutter not found on PATH or at ~/development/flutter/bin." >&2
  exit 1
fi

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

echo "Building IPA with: $REQUIRED_KEYS"
"$FLUTTER" build ipa "${define_args[@]}" "$@"
