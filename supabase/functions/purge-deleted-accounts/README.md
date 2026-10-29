# purge-deleted-accounts

Hard-deletes auth users whose `profiles.deletion_requested_at` is older than 7 days
(see view `profiles_due_for_purge`).

## Auth

The function accepts **either**:

1. Header `x-purge-secret` matching Edge Function secret `PURGE_SECRET` (optional), or
2. `Authorization: Bearer <service_role JWT or key>`

Anon / authenticated user JWTs are rejected. If `PURGE_SECRET` is unset, only the
service_role Bearer path works (this is what the pg_cron job uses).

## Deploy

```bash
supabase functions deploy purge-deleted-accounts --project-ref iovnmgwthmevvvtszhrq
```

## Schedule (daily 03:00 UTC)

Installed on the linked project as pg_cron job `purge-deleted-accounts-daily`
(`0 3 * * *`), which POSTs to this function via `pg_net` using Vault secrets
`purge_project_url` + `purge_service_role_key`.

Manual invoke:

```bash
curl -X POST "%SUPABASE_URL%/functions/v1/purge-deleted-accounts" ^
  -H "Authorization: Bearer %SUPABASE_SERVICE_ROLE_KEY%"
```

Signing in during the 7-day window cancels pending deletion via
`cancel_account_deletion()` RPC (ProfileService).
