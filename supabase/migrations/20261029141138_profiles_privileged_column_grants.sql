-- Table-level UPDATE/INSERT trump column REVOKE. Re-grant DML only on
-- non-privileged columns so clients cannot write is_admin / deletion_requested_at.

revoke insert, update on table public.profiles from anon, authenticated;

grant insert (
  id,
  display_name,
  avatar_url,
  created_at,
  updated_at
) on table public.profiles to anon, authenticated;

grant update (
  id,
  display_name,
  avatar_url,
  created_at,
  updated_at
) on table public.profiles to anon, authenticated;

-- SELECT/DELETE stay at table level (RLS still applies). is_admin and
-- deletion_requested_at remain readable so the app can show admin/delete state.
grant select, delete on table public.profiles to anon, authenticated;
