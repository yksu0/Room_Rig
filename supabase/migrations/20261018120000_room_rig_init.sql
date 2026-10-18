-- Room Rig v1: profiles + rooms with RLS (auth.uid()).
-- Apply on a dedicated Supabase project (not shared with other apps).

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create table if not exists public.rooms (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  preset_name text not null default 'gamingSetup',
  scan_complete boolean not null default false,
  scan_progress double precision not null default 0,
  layout jsonb not null default '{}'::jsonb,
  furniture jsonb not null default '[]'::jsonb,
  revisions jsonb not null default '[]'::jsonb,
  installed_upgrades jsonb not null default '[]'::jsonb,
  original_furniture jsonb,
  original_scores jsonb,
  scores_clean boolean not null default false,
  is_optimized boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists rooms_user_id_updated_at_idx
  on public.rooms (user_id, updated_at desc);

alter table public.rooms enable row level security;

create policy "rooms_select_own"
  on public.rooms for select
  using (auth.uid() = user_id);

create policy "rooms_insert_own"
  on public.rooms for insert
  with check (auth.uid() = user_id);

create policy "rooms_update_own"
  on public.rooms for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "rooms_delete_own"
  on public.rooms for delete
  using (auth.uid() = user_id);

-- Auto-create profile row on signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
