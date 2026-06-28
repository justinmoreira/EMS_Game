-- Harden the new-user → profile bootstrap so it can NEVER break auth.
--
-- The on_auth_user_created trigger (20260625000000) inserts a row into
-- public.profiles when GoTrue creates a user. If that insert throws — or the
-- role GoTrue runs as (supabase_auth_admin) lacks the grants to reach the
-- table — GoTrue surfaces it as "Database error saving new user" / "Database
-- error querying schema" and sign-up/sign-in fails outright. Profile creation
-- is non-essential to authentication, so make it strictly best-effort:
--   • wrap the insert in an exception handler (a failure is swallowed, the
--     user is still created — ensureProfile() on the client backfills later);
--   • grant supabase_auth_admin the access the trigger needs, the documented
--     fix for triggers on auth.users that touch a public table.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into public.profiles (id, display_name)
    values (
      new.id,
      coalesce(
        nullif(new.raw_user_meta_data ->> 'display_name', ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Player'
      )
    )
    on conflict (id) do nothing;
  exception
    when others then
      -- Never let a profile hiccup block authentication.
      raise warning 'handle_new_user: profile insert failed for %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

-- Let the GoTrue admin role reach the function and the table.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.handle_new_user() to supabase_auth_admin;
grant insert, select on table public.profiles to supabase_auth_admin;
