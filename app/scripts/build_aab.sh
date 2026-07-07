#!/usr/bin/env bash
# Builds a release Android App Bundle (.aab) for the Play Store, with every
# --dart-define the app needs read from dart_defines.env (same source of truth
# as build_ipa.sh — see that script's header for why this exists).
#
# Prerequisites (one-time):
#   1. Generate an upload keystore, kept OUTSIDE the repo:
#        keytool -genkey -v -keystore ~/keys/kitabi-upload.jks \
#          -keyalg RSA -keysize 2048 -validity 10000 -alias upload
#   2. cp android/key.properties.example android/key.properties  and fill it in.
#
# Output: build/app/outputs/bundle/release/app-release.aab — upload this to the
# Play Console (Internal testing → Create release).
set -euo pipefail
cd "$(dirname "$0")/.."

# Locate flutter — on PATH if the user set it up, else the known SDK location
# (CLAUDE.md: SDK at ~/development/flutter, not on the default PATH).
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

if [[ ! -f "android/key.properties" ]]; then
  echo "error: android/key.properties not found — the AAB would be debug-signed and" >&2
  echo "Play would reject it. Copy android/key.properties.example and fill it in." >&2
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

echo "Building AAB with: $REQUIRED_KEYS"
"$FLUTTER" build appbundle "${define_args[@]}" "$@"
echo
echo "✓ AAB: build/app/outputs/bundle/release/app-release.aab"
