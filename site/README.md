# Room Rig storefront (`site/`)

Public marketing site deployed to Vercel (`roomrig.vercel.app`).

**Not** the Flutter web app. Product use is the Android APK (GitHub Releases when a named build is cut).

## Pages

| Path | Purpose |
|------|---------|
| `/` | Product description + Hub → Room → Scan → Benchmark loop |
| `/auth` | Supabase email + Google web OAuth |
| `/download` | Links to GitHub Releases (APK upload separate; placeholder OK) |
| `/admin` | Stub gated by `profiles.is_admin` |

## Local preview

```bash
# Optional: copy config.example.js → config.local.js and point index scripts at it,
# or export keys and run:
export SUPABASE_URL=…
export SUPABASE_ANON_KEY=…
bash scripts/build_site.sh
npx serve build/site
```

## Auth notes

- Keep `https://roomrig.vercel.app/**` on the Supabase redirect allow list for **this site**.
- Native Android Google Sign-In does **not** use Vercel.
- Mobile email deep link stays `com.roomrig.room_rig://login-callback/`.
