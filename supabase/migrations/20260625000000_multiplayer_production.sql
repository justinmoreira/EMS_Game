-- Multiplayer: production lobby + leaderboard layer.
--
-- Builds on 20260529000000_create_multiplayer.sql (matches + match_actions +
-- both-submitted turn trigger). Adds:
--   • named, public/private lobbies with shareable invite codes
--   • a server-recorded win condition (status='finished', winner_id)
--   • profiles (display name + W/L/D) backing an open leaderboard
--   • finish_match(): idempotent, SECURITY DEFINER win recorder that bumps
--     both players' leaderboard tallies exactly once per match
--
-- The win is computed deterministically on BOTH clients from the merged board
-- (same seed, same immutable units, same physics), so they agree on the
-- winner; finish_match's status guard makes the second caller a no-op.


-- ── matches: lobby metadata + outcome ────────────────────────────────────
alter table "public"."matches"
  add column if not exists "name" text not null default 'Match',
  add column if not exists "visibility" text not null default 'public',
  add column if not exists "invite_code" text,
  add column if not exists "max_turns" integer not null default 30,
  add column if not exists "winner_id" uuid,
  add column if not exists "finished_at" timestamp with time zone;

alter table "public"."matches"
  drop constraint if exists "matches_visibility_check";
alter table "public"."matches"
  add constraint "matches_visibility_check"
  check (visibility in ('public', 'private'));

alter table "public"."matches"
  drop constraint if exists "matches_status_check";
alter table "public"."matches"
  add constraint "matches_status_check"
  check (status in ('waiting', 'active', 'finished', 'abandoned'));

alter table "public"."matches"
  drop constraint if exists "matches_winner_id_fkey";
alter table "public"."matches"
  add constraint "matches_winner_id_fkey"
  foreign key (winner_id) references auth.users(id) on delete set null;

create unique index if not exists matches_invite_code_key
  on public.matches (invite_code) where invite_code is not null;

-- Public, still-open lobbies are the hot path for the lobby browser.
create index if not exists matches_browse_idx
  on public.matches (visibility, status, created_at desc);


-- ── profiles: display name + leaderboard tallies ─────────────────────────
create table if not exists "public"."profiles" (
  "id" uuid not null,
  "display_name" text not null default '',
  "wins" integer not null default 0,
  "losses" integer not null default 0,
  "draws" integer not null default 0,
  "games_played" integer not null default 0,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "public"."profiles" enable row level security;

create unique index if not exists profiles_pkey on public.profiles using btree (id);
alter table "public"."profiles"
  drop constraint if exists "profiles_pkey";
alter table "public"."profiles"
  add constraint "profiles_pkey" primary key using index "profiles_pkey";

alter table "public"."profiles"
  drop constraint if exists "profiles_id_fkey";
alter table "public"."profiles"
  add constraint "profiles_id_fkey"
  foreign key (id) references auth.users(id) on delete cascade;

-- Leaderboard ordering index.
create index if not exists profiles_leaderboard_idx
  on public.profiles (wins desc, losses asc);


-- ── match_results: immutable audit trail of finished matches ─────────────
create table if not exists "public"."match_results" (
  "match_id" text not null,
  "winner_id" uuid,
  "loser_id" uuid,
  "is_draw" boolean not null default false,
  "finished_at" timestamp with time zone not null default now()
);

alter table "public"."match_results" enable row level security;

create unique index if not exists match_results_pkey
  on public.match_results using btree (match_id);
alter table "public"."match_results"
  drop constraint if exists "match_results_pkey";
alter table "public"."match_results"
  add constraint "match_results_pkey" primary key using index "match_results_pkey";

alter table "public"."match_results"
  drop constraint if exists "match_results_match_id_fkey";
alter table "public"."match_results"
  add constraint "match_results_match_id_fkey"
  foreign key (match_id) references public.matches(id) on delete cascade;


-- ── RLS ──────────────────────────────────────────────────────────────────

-- profiles: everyone authenticated can read (leaderboard + opponent names);
-- a user may create/update only their own row, and only the display_name is
-- meant to be user-editable — the tally columns move through finish_match()
-- (SECURITY DEFINER) so a player can't inflate their own win count.
drop policy if exists "Profiles are readable by authenticated" on "public"."profiles";
create policy "Profiles are readable by authenticated"
  on "public"."profiles" as permissive for select to authenticated using (true);

drop policy if exists "Users can insert own profile" on "public"."profiles";
create policy "Users can insert own profile"
  on "public"."profiles" as permissive for insert to authenticated
  with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on "public"."profiles";
create policy "Users can update own profile"
  on "public"."profiles" as permissive for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- match_results: read-only to clients; writes happen only inside finish_match.
drop policy if exists "Match results readable by authenticated" on "public"."match_results";
create policy "Match results readable by authenticated"
  on "public"."match_results" as permissive for select to authenticated using (true);


-- ── profile bootstrap: auto-create a row on signup ───────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(new.email, '@', 1),
      'Player'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill profiles for users that predate this migration.
insert into public.profiles (id, display_name)
select u.id, coalesce(nullif(split_part(u.email, '@', 1), ''), 'Player')
from auth.users u
on conflict (id) do nothing;


-- ── updated_at trigger for profiles ──────────────────────────────────────
drop trigger if exists on_profiles_updated on public.profiles;
create trigger on_profiles_updated
  before update on public.profiles
  for each row execute function public.handle_updated_at();


-- ── finish_match(): idempotent win recorder ──────────────────────────────
-- Called by the first client to detect the end of the match. Guards on
-- status so a duplicate call (the other client, a realtime echo) is a no-op.
-- p_winner_id null  → draw (both players' games_played + draws bump).
-- p_winner_id set   → that player +win, the other +loss.
create or replace function public.finish_match(p_match_id text, p_winner_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.matches%rowtype;
  v_loser uuid;
  v_is_draw boolean;
begin
  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match % not found', p_match_id;
  end if;

  -- Already finished → nothing to do (idempotent).
  if m.status = 'finished' then
    return;
  end if;

  -- The caller must be a participant.
  if auth.uid() is null or (auth.uid() <> m.host_id and auth.uid() <> m.guest_id) then
    raise exception 'only participants can finish a match';
  end if;

  v_is_draw := p_winner_id is null;

  if not v_is_draw then
    if p_winner_id <> m.host_id and p_winner_id <> m.guest_id then
      raise exception 'winner must be a participant';
    end if;
    v_loser := case when p_winner_id = m.host_id then m.guest_id else m.host_id end;
  end if;

  update public.matches
    set status = 'finished', winner_id = p_winner_id, finished_at = now(), updated_at = now()
    where id = p_match_id;

  insert into public.match_results (match_id, winner_id, loser_id, is_draw, finished_at)
    values (p_match_id, p_winner_id, v_loser, v_is_draw, now())
    on conflict (match_id) do nothing;

  -- Leaderboard tallies. Guard each update so a missing profile row never
  -- aborts the finish.
  if v_is_draw then
    update public.profiles set draws = draws + 1, games_played = games_played + 1
      where id in (m.host_id, m.guest_id);
  else
    update public.profiles set wins = wins + 1, games_played = games_played + 1
      where id = p_winner_id;
    update public.profiles set losses = losses + 1, games_played = games_played + 1
      where id = v_loser;
  end if;
end;
$$;

grant execute on function public.finish_match(text, uuid) to authenticated;


-- ── Realtime ─────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    -- matches + match_actions are already in the publication from the earlier
    -- migration; add the new tables. Guard each so re-runs don't error.
    begin
      alter publication supabase_realtime add table public.profiles;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.match_results;
    exception when duplicate_object then null;
    end;
  end if;
end $$;


-- ── grants (mirror sandbox_states for PostgREST exposure) ────────────────
grant select, insert, update, delete on table "public"."profiles" to "authenticated";
grant select on table "public"."profiles" to "anon";
grant select, insert, update, delete on table "public"."profiles" to "service_role";

grant select on table "public"."match_results" to "authenticated";
grant select on table "public"."match_results" to "service_role";
