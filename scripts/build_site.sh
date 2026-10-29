#!/usr/bin/env bash
# Build the Next.js storefront under site/.
# Prefer Vercel Git integration with Root Directory = site.
# Env (public): NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, NEXT_PUBLIC_GITHUB_REPO
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/site"

if [[ -z "${NEXT_PUBLIC_SUPABASE_URL:-${SUPABASE_URL:-}}" || -z "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-${SUPABASE_ANON_KEY:-}}" ]]; then
  echo "Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY (or SUPABASE_URL / SUPABASE_ANON_KEY)." >&2
  exit 1
fi

export NEXT_PUBLIC_SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL:-$SUPABASE_URL}"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="${NEXT_PUBLIC_SUPABASE_ANON_KEY:-$SUPABASE_ANON_KEY}"
export NEXT_PUBLIC_GITHUB_REPO="${NEXT_PUBLIC_GITHUB_REPO:-yksu0/Room_Rig}"

npm ci
npm run build
echo "Next build OK under $ROOT/site (.next). Deploy via Vercel (Root Directory=site) or vercel deploy --prebuilt."
