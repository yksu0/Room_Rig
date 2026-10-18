# Room Rig — Supabase

Free-tier orgs are limited to **2 active projects**. Creating `room-rig` failed because both existing projects are in use. Free a slot (pause/delete an unused project) or upgrade, then:

1. Create project `room-rig` (region `ap-southeast-1` recommended).
2. Run SQL in [migrations/20261018120000_room_rig_init.sql](migrations/20261018120000_room_rig_init.sql) (SQL editor or CLI).
3. Auth → Email enabled; Confirm email **off** until Brevo SMTP works, then turn **on**.
4. Auth → URL: Site URL + redirect `http://localhost:7357`.
5. Auth → SMTP: Brevo credentials.
6. Copy Project URL + anon key into gitignored `supabase.local.json` (see example) and run:

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
