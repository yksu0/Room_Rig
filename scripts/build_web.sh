#!/usr/bin/env bash
# Production Flutter web build for Vercel (CI or local).
# Requires: flutter on PATH, SUPABASE_URL + SUPABASE_ANON_KEY in env.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Set SUPABASE_URL and SUPABASE_ANON_KEY (Vercel/GitHub secrets or export)." >&2
  exit 1
fi

flutter pub get
flutter build web --release \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"

echo "Output: $ROOT/build/web"
