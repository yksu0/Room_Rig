-- Community needs public author identity (name/avatar) without exposing
-- soft-delete / is_admin flags. Also lock down SECURITY DEFINER RPCs.

-- ---------------------------------------------------------------------------
-- community_profiles: safe public identity for feed hydration
-- ---------------------------------------------------------------------------
create or replace view public.community_profiles
with (security_invoker = false)
as
select
  id,
  display_name,
  avatar_url
from public.profiles;

comment on view public.community_profiles is
  'Public Community identity only (id, display_name, avatar_url). '
  'Does not expose deletion_requested_at or is_admin.';

revoke all on public.community_profiles from public;
grant select on public.community_profiles to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Harden SECURITY DEFINER helpers (advisor: callable via /rest/v1/rpc)
-- handle_new_user is for the auth trigger only — not client RPC.
-- ---------------------------------------------------------------------------
revoke all on function public.handle_new_user() from public;
revoke all on function public.handle_new_user() from anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;
grant execute on function public.handle_new_user() to postgres;
grant execute on function public.handle_new_user() to service_role;

revoke all on function public.rls_auto_enable() from public;
revoke all on function public.rls_auto_enable() from anon, authenticated;

-- Mutable search_path on touch_updated_at
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
