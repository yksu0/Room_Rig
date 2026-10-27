# purge-deleted-accounts

Hard-deletes auth users whose `profiles.deletion_requested_at` is older than 7 days
(see view `profiles_due_for_purge`).

## Deploy

```bash
supabase functions deploy purge-deleted-accounts --project-ref iovnmgwthmevvvtszhrq
```

Optional: set secret `PURGE_SECRET` and pass header `x-purge-secret` on manual POSTs.

## Schedule (daily 03:00 UTC)

Installed on the linked project as pg_cron job `purge-deleted-accounts-daily`
(`0 3 * * *`), which POSTs to this function via `pg_net` using Vault secrets
`purge_project_url` + `purge_service_role_key`.

Dashboard alternative: Integrations → Cron, or Edge Functions → Schedules.

Manual invoke:

```bash
curl -X POST "%SUPABASE_URL%/functions/v1/purge-deleted-accounts" ^
  -H "Authorization: Bearer %SUPABASE_SERVICE_ROLE_KEY%" ^
  -H "x-purge-secret: %PURGE_SECRET%"
```

Signing in during the 7-day window cancels pending deletion (ProfileService clears
`deletion_requested_at`).
