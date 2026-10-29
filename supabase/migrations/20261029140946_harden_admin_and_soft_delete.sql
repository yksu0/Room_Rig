-- Harden profiles.is_admin + deletion_requested_at against client writes.
-- Soft-delete mark/cancel only via SECURITY DEFINER RPCs (OTP verified in app first).

revoke insert (is_admin, deletion_requested_at) on table public.profiles from anon, authenticated;
revoke update (is_admin, deletion_requested_at) on table public.profiles from anon, authenticated;

comment on column public.profiles.is_admin is
  'Web admin panel gate. Writable only by service_role / SQL editor — never by clients. '
  'Flip: UPDATE profiles SET is_admin = true WHERE id = … (as postgres/service_role).';

comment on column public.profiles.deletion_requested_at is
  'Set only via public.request_account_deletion() after email OTP. Cleared via '
  'public.cancel_account_deletion() on a fresh authenticated session. Hard purge after 7 days.';

create or replace function public.profiles_protect_privileged_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin', 'supabase_auth_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if coalesce(new.is_admin, false) is distinct from false then
      raise exception 'is_admin is not client-writable';
    end if;
    if new.deletion_requested_at is not null then
      raise exception 'deletion_requested_at is not client-writable; use request_account_deletion()';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.is_admin is distinct from old.is_admin then
      raise exception 'is_admin is not client-writable';
    end if;
    if new.deletion_requested_at is distinct from old.deletion_requested_at then
      raise exception 'deletion_requested_at is not client-writable; use request_account_deletion() / cancel_account_deletion()';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_privileged_columns on public.profiles;
create trigger profiles_protect_privileged_columns
  before insert or update on public.profiles
  for each row execute function public.profiles_protect_privileged_columns();

revoke all on function public.profiles_protect_privileged_columns() from public;
revoke all on function public.profiles_protect_privileged_columns() from anon, authenticated;

create or replace function public.request_account_deletion()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ts timestamptz := now();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set deletion_requested_at = ts,
      updated_at = ts
  where id = uid;

  if not found then
    insert into public.profiles (id, deletion_requested_at)
    values (uid, ts);
  end if;

  return ts;
end;
$$;

create or replace function public.cancel_account_deletion()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cleared boolean := false;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set deletion_requested_at = null,
      updated_at = now()
  where id = uid
    and deletion_requested_at is not null;

  cleared := found;
  return cleared;
end;
$$;

revoke all on function public.request_account_deletion() from public;
revoke all on function public.request_account_deletion() from anon;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.request_account_deletion() to service_role;

revoke all on function public.cancel_account_deletion() from public;
revoke all on function public.cancel_account_deletion() from anon;
grant execute on function public.cancel_account_deletion() to authenticated;
grant execute on function public.cancel_account_deletion() to service_role;

comment on function public.request_account_deletion() is
  'Marks the caller profile for deletion (7-day grace). Call only after email OTP verify.';
comment on function public.cancel_account_deletion() is
  'Clears pending soft-delete for the caller. Requires authenticated session (e.g. sign-in).';
