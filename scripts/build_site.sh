#!/usr/bin/env bash
# Inject Supabase public keys into the marketing site and stage deploy output.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Set SUPABASE_URL and SUPABASE_ANON_KEY (Vercel/GitHub secrets or export)." >&2
  exit 1
fi

OUT="$ROOT/build/site"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$ROOT/site/." "$OUT/"

# Escape for JS string literals.
escape_js() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

URL_ESC="$(escape_js "$SUPABASE_URL")"
KEY_ESC="$(escape_js "$SUPABASE_ANON_KEY")"

cat > "$OUT/config.js" <<EOF
window.ROOM_RIG_SITE = {
  supabaseUrl: "${URL_ESC}",
  supabaseAnonKey: "${KEY_ESC}",
  githubReleasesUrl: "https://github.com/yksu0/Room_Rig/releases",
  appDeepLink: "com.roomrig.room_rig://login-callback/",
};
EOF

cp "$ROOT/site/vercel.json" "$OUT/vercel.json"
echo "Output: $OUT"
