-- Fix missing table grants (PostgREST was returning permission denied for
-- authenticated users on profiles/rooms — delete/profile/sync all failed) and
-- stop seeding Google name/photo into profiles. App identity is set only in Profile.

-- ---------------------------------------------------------------------------
-- Grants: RLS alone is not enough — roles need table privileges too.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on table public.profiles
  to anon, authenticated, service_role;

grant select, insert, update, delete on table public.rooms
  to anon, authenticated, service_role;

-- Purge Edge Function reads this view with the service role.
grant select on public.profiles_due_for_purge to service_role;

-- ---------------------------------------------------------------------------
-- handle_new_user: create a blank app profile (no Google name / picture).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (new.id, null, null)
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on column public.profiles.display_name is
  'App-owned public handle (Profile editor). Never seeded from Google/OAuth metadata.';
comment on column public.profiles.avatar_url is
  'App-owned avatar URL in the avatars bucket (Profile picker). Never seeded from Google.';

-- Drop Google-hosted avatar URLs that were written by the previous seed path.
update public.profiles
set avatar_url = null,
    updated_at = now()
where avatar_url is not null
  and (
    avatar_url ilike '%googleusercontent.com%'
    or avatar_url ilike '%lh3.google.com%'
    or avatar_url ilike '%ggpht.com%'
  );
