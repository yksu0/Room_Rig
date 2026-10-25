# Room Rig — Supabase

Free-tier orgs are limited to **2 active projects**. Creating `room-rig` failed because both existing projects are in use. Free a slot (pause/delete an unused project) or upgrade, then:

1. Create project `room-rig` (region `ap-southeast-1` recommended).
2. Run SQL in [migrations/20261018120000_room_rig_init.sql](migrations/20261018120000_room_rig_init.sql) (SQL editor or CLI).
3. Auth → Email enabled; Confirm email **off** until Brevo SMTP works, then turn **on**.
4. Auth → URL Configuration (hosted project — required for Android auth handoff):
   - Site URL: `https://roomrig.vercel.app` (or `http://localhost:7357` while web-only testing).
   - Redirect URLs allow list — add **all** of:
     - `http://localhost:7357/**`
     - `https://roomrig.vercel.app/**`
     - `com.roomrig.room_rig://login-callback/**`  
       Required for Android: Google sign-in, email confirm, and password reset. Without it the phone opens a website instead of Room Rig.
5. Auth → Providers → **Google** (Free tier): enable, paste Client ID + Client Secret from Google Cloud Console (OAuth 2.0 Web client). Authorized redirect URI = Supabase callback shown in the provider panel (`https://YOUR_PROJECT.supabase.co/auth/v1/callback`).
6. Auth → SMTP: Brevo credentials (optional for email/password).
7. Copy Project URL + anon key into gitignored `supabase.local.json` (see example) and run:

```powershell
.\scripts\dev_web.ps1
```

Or:

```powershell
flutter run -d web-server --web-port 7357 `
  --dart-define=SUPABASE_URL=https://YOUR.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Without keys the app runs **guest-only** (local My Rooms).

## Production (Vercel)

Localhost is for you only. Shared access uses a Vercel URL (`*.vercel.app` or custom domain).

1. `vercel login` (CLI) → create/link project (see repo `vercel.json`).
2. GitHub Actions [`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml) builds Flutter web and deploys `build/web`.
3. Repo secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.
4. After first deploy, add the production origin to Supabase Auth URL allow list **and** Google OAuth JS origins (keep localhost too).
