# Room Rig — Supabase

Free-tier orgs are limited to **2 active projects**. Creating `room-rig` failed because both existing projects are in use. Free a slot (pause/delete an unused project) or upgrade, then:

1. Create project `room-rig` (region `ap-southeast-1` recommended).
2. Apply migrations with `supabase db push` (or SQL editor), including:
   - [migrations/20261018120000_room_rig_init.sql](migrations/20261018120000_room_rig_init.sql)
   - [migrations/20261027120000_profiles_avatar_soft_delete.sql](migrations/20261027120000_profiles_avatar_soft_delete.sql) — `profiles.avatar_url` / `deletion_requested_at`, `avatars` bucket, `profiles_due_for_purge`
   - [migrations/20261028140000_published_layouts_social.sql](migrations/20261028140000_published_layouts_social.sql) — Community `published_layouts` / `layout_ratings`, `layout_rating_stats`, `monthly_featured_layouts`, `profiles.is_admin`, seeded baselines
   - Deploy `functions/purge-deleted-accounts` and schedule it daily (pg_cron job uses service_role Bearer — see [functions/purge-deleted-accounts/README.md](functions/purge-deleted-accounts/README.md)). Soft-delete is set via `request_account_deletion()` after OTP (or the `delete-account` Edge Function); signing in cancels via `cancel_account_deletion()`. Hard purge runs after 7 days.
   - Email Templates → **Magic Link**: paste `email_templates/magic_link.html` (keeps `{{ .Token }}` so the in-app 6-digit confirm works).
   - Admin storefront access: `UPDATE profiles SET is_admin = true WHERE id = '…';`
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

## Social layer (mobile Benchmark → Community)

Shipped in the Android app + `published_layouts` migration:

- Guests may **browse** the feed; **publish / rate / clone / Compare / Apply** require sign-in.
- Publish / rate also require a complete Profile (`display_name` + `avatar_url`).
- Ratings are up/down + optional tags (airflow / lighting / ergonomics / spatial).
- Admin baselines are SQL-seeded (`is_admin_baseline`); clients cannot set that flag.
- Monthly top-3 view: `monthly_featured_layouts` (empty until prior-month rating activity).
- Report / hide UI is later; `hidden` + `author_id` are already on the table.

## Production (Vercel storefront)

Vercel hosts the **marketing site** in [`site/`](../site/) — product description, Sign in / Sign up, Download (GitHub Releases link), Admin stub. It does **not** host the Flutter web customizer.

1. `vercel login` (CLI) → create/link project (see repo `vercel.json` / `site/vercel.json`).
2. GitHub Actions [`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml) runs `scripts/build_site.sh` and deploys `build/site`.
3. Repo secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.
4. Keep `https://roomrig.vercel.app/**` on the Auth redirect allow list for **storefront** OAuth. Native Android Google Sign-In does not use Vercel.
5. Download page points at GitHub Releases; uploading an APK asset is a separate release step (suggested tag style `v1.0.0+1`, not locked).
