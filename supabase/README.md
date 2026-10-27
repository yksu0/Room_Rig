# Room Rig — Supabase

Free-tier orgs are limited to **2 active projects**. Creating `room-rig` failed because both existing projects are in use. Free a slot (pause/delete an unused project) or upgrade, then:

1. Create project `room-rig` (region `ap-southeast-1` recommended).
2. Run SQL in [migrations/20261018120000_room_rig_init.sql](migrations/20261018120000_room_rig_init.sql), then [migrations/20261027120000_profiles_avatar_soft_delete.sql](migrations/20261027120000_profiles_avatar_soft_delete.sql) (SQL editor or CLI). The second one adds `profiles.avatar_url` / `deletion_requested_at`, the public `avatars` Storage bucket, and the `profiles_due_for_purge` view.
   - Deploy `functions/purge-deleted-accounts` and schedule it daily (Edge Functions → Schedules, cron `0 3 * * *`). It hard-deletes accounts 7 days after the in-app OTP-confirmed delete; signing in within the window cancels.
   - Email Templates → **Magic Link**: paste `email_templates/magic_link.html` (keeps `{{ .Token }}` so the in-app 6-digit confirm works).
3. Auth → Email enabled; Confirm email **off** until Brevo SMTP works, then turn **on**.
4. Auth → URL Configuration (hosted project — required for Android auth handoff):
   - Site URL: `https://roomrig.vercel.app` (or `http://localhost:7357` while web-only testing).
   - Redirect URLs allow list — add **all** of:
     - `http://localhost:7357/**`
     - `https://roomrig.vercel.app/**`
     - `com.roomrig.room_rig://login-callback/**`  
       Required for Android email confirm / password reset deep links.
5. Auth → Providers → **Google** (Free tier): enable, paste Client ID + Client Secret from Google Cloud Console (OAuth 2.0 **Web** client). Authorized redirect URI = Supabase callback (`https://YOUR_PROJECT.supabase.co/auth/v1/callback`).
6. **Android Google (native, no Chrome):** In the **same** Google Cloud project as the Web client from step 5 → APIs & Services → Credentials → Create Credentials → OAuth client ID → Application type **Android**:
   - Package name: `com.roomrig.room_rig`
   - SHA-1 (debug): `6C:10:FA:51:E8:C4:9F:B9:E3:93:18:93:8A:55:3A:3D:AE:64:F8:AE`
   - Without this, picking an account often shows “cancelled” (Credential Manager mislabels config errors).
   - Put the **Web** client ID into `supabase.local.json` as `GOOGLE_WEB_CLIENT_ID` (same ID as step 5). Build with `.\scripts\install_android.ps1`.
7. Auth → SMTP: Brevo credentials (optional for email/password).
8. Copy Project URL + anon key (+ `GOOGLE_WEB_CLIENT_ID`) into gitignored `supabase.local.json` (see example) and run:

```powershell
.\scripts\dev_web.ps1
```

Or:

```powershell
flutter run -d web-server --web-port 7357 `
  --dart-define=SUPABASE_URL=https://YOUR.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY `
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Without keys the app runs **guest-only** (local My Rooms). Guests own exactly **one** room; creating a second one is a hard sign-up gate, and the guest room is force-claimed into the account on first sign-in.

## Social layer (not built yet — constraints to keep)

No social UI ships today. The Profile page and schema are shaped so the Benchmark social layer can land without migrations that break existing rows:

- Users publish **full layouts** (not just scores); others can clone or compare against them.
- Ratings are **up/down + tagged criteria** (airflow / lighting / ergonomics / spatial), one row per rater per layout.
- **Admin-authored baselines** first; community top-3 monthly later.
- Publishing or rating requires `profiles.display_name` **and** `profiles.avatar_url` (both already editable on Profile).
- Moderation hooks (report / hide) are a later step; keep author ids on every public row so they are possible.

Table sketches live as comments at the bottom of `migrations/20261027120000_profiles_avatar_soft_delete.sql`.

## Production (Vercel)

Localhost is for you only. Shared access uses a Vercel URL (`*.vercel.app` or custom domain).

1. `vercel login` (CLI) → create/link project (see repo `vercel.json`).
2. GitHub Actions [`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml) builds Flutter web and deploys `build/web`.
3. Repo secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.
4. After first deploy, add the production origin to Supabase Auth URL allow list **and** Google OAuth JS origins (keep localhost too).
