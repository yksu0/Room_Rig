#!/usr/bin/env bash
# Build the Next.js storefront under site/ (Node 22.x; see site/.nvmrc and package.json engines).
# Prefer Vercel Git integration with Root Directory = site.
# Vercel CLI (pull/build/deploy) must run from the repo root when Root Directory=site
# (cwd=site/ doubles to site/site — vercel/vercel#17735). See .github/workflows/deploy-web.yml.
# Env (public): NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, NEXT_PUBLIC_GITHUB_REPO
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/site"

if [[ -z "${NEXT_PUBLIC_SUPABASE_URL:-${SUPABASE_URL:-}}" || -z "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-${SUPABASE_ANON_KEY:-}}" ]]; then
  echo "ERROR: Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY (or SUPABASE_URL / SUPABASE_ANON_KEY)." >&2
  exit 1
fi

export NEXT_PUBLIC_SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL:-$SUPABASE_URL}"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="${NEXT_PUBLIC_SUPABASE_ANON_KEY:-$SUPABASE_ANON_KEY}"
export NEXT_PUBLIC_GITHUB_REPO="${NEXT_PUBLIC_GITHUB_REPO:-yksu0/Room_Rig}"

npm ci
npm run build
echo "Next build OK under $ROOT/site (.next). Deploy via Vercel Git (Root Directory=site) or workflow vercel CLI from repo root."
