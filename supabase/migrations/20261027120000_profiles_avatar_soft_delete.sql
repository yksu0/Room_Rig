-- Room Rig v2: profile avatar + name editing, avatar storage bucket,
-- 7-day soft delete, and forward-compat notes for the social layer.
-- Apply after 20261018120000_room_rig_init.sql.

-- ---------------------------------------------------------------------------
-- profiles: avatar + soft-delete window
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

comment on column public.profiles.display_name is
  'Public handle. Required (with avatar_url) before a user may publish layouts or rate.';
comment on column public.profiles.avatar_url is
  'Public URL into the avatars bucket (or the Google photo seeded at first sign-in).';
comment on column public.profiles.deletion_requested_at is
  'Set after the user confirms deletion by email OTP. Hard purge runs 7 days later; '
  'a sign-in inside the window clears it (cancels deletion).';

-- Seed display_name + avatar from the auth provider (Google sends avatar_url / picture).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name',
             new.raw_user_meta_data->>'full_name',
             new.raw_user_meta_data->>'name',
             split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'avatar_url',
             new.raw_user_meta_data->>'picture')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Storage: avatars bucket (public read, owner-only write under <uid>/...)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152, -- 2 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ---------------------------------------------------------------------------
-- Soft delete helpers (called by the purge-deleted-accounts Edge Function
-- with the service role; RLS does not apply to service role).
-- ---------------------------------------------------------------------------
create index if not exists profiles_deletion_requested_at_idx
  on public.profiles (deletion_requested_at)
  where deletion_requested_at is not null;

-- Rows whose 7-day grace window has elapsed. The Edge Function deletes the
-- auth user; profiles + rooms cascade from auth.users.
create or replace view public.profiles_due_for_purge as
  select id, deletion_requested_at
  from public.profiles
  where deletion_requested_at is not null
    and deletion_requested_at <= now() - interval '7 days';

revoke all on public.profiles_due_for_purge from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Forward-compat notes (NOT created yet — see docs in plan "social-constraints").
-- When the Benchmark social layer ships, add:
--   public.published_layouts (id, author_id -> profiles, room jsonb full layout,
--                             title, tags text[], is_admin_baseline bool, published_at)
--   public.layout_ratings    (layout_id, rater_id, vote smallint check (vote in (-1, 1)),
--                             tags text[] /* 'airflow','lighting','ergonomics','spatial' */,
--                             primary key (layout_id, rater_id))
--   publish/rate RLS must require profiles.display_name and avatar_url not null.
-- ---------------------------------------------------------------------------
