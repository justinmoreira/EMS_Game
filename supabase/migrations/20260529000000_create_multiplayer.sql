-- Multiplayer PoC: a single hard-coded lobby ('poc-lobby') where two
-- players each submit one action per turn. A trigger advances
-- matches.current_turn once both submissions for that turn have landed;
-- clients observe both the new actions and the turn bump via Realtime
-- and converge on a shared state.
--
-- Out of scope for the PoC: matchmaking, multi-room support, action
-- validation, server-side game logic, win conditions. The `action` jsonb
-- is opaque — the schema only enforces "one row per (match, turn, player)".


  create table "public"."matches" (
    "id" text not null,
    "seed" bigint not null,
    "host_id" uuid,
    "guest_id" uuid,
    "current_turn" integer not null default 0,
    "status" text not null default 'waiting'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."matches" enable row level security;

CREATE UNIQUE INDEX matches_pkey ON public.matches USING btree (id);

alter table "public"."matches" add constraint "matches_pkey" PRIMARY KEY using index "matches_pkey";

alter table "public"."matches" add constraint "matches_host_id_fkey"
  FOREIGN KEY (host_id) REFERENCES auth.users(id) ON DELETE SET NULL;

alter table "public"."matches" add constraint "matches_guest_id_fkey"
  FOREIGN KEY (guest_id) REFERENCES auth.users(id) ON DELETE SET NULL;


  create table "public"."match_actions" (
    "match_id" text not null,
    "turn_number" integer not null,
    "player_id" uuid not null,
    "action" jsonb not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."match_actions" enable row level security;

CREATE UNIQUE INDEX match_actions_pkey ON public.match_actions USING btree (match_id, turn_number, player_id);

alter table "public"."match_actions" add constraint "match_actions_pkey" PRIMARY KEY using index "match_actions_pkey";

alter table "public"."match_actions" add constraint "match_actions_match_id_fkey"
  FOREIGN KEY (match_id) REFERENCES public.matches(id) ON DELETE CASCADE;

alter table "public"."match_actions" add constraint "match_actions_player_id_fkey"
  FOREIGN KEY (player_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- RLS: matches readable by any authenticated user (PoC has one shared
-- lobby anyway); writable by participants. The guest_id-is-null clause
-- on update lets a second player claim the empty guest seat.

create policy "Authenticated users can read matches"
  on "public"."matches" as permissive for select to authenticated using (true);

create policy "Authenticated users can create matches"
  on "public"."matches" as permissive for insert to authenticated
  with check (auth.uid() = host_id);

create policy "Participants can update matches"
  on "public"."matches" as permissive for update to authenticated
  using (auth.uid() = host_id or auth.uid() = guest_id or guest_id is null);


create policy "Authenticated users can read match actions"
  on "public"."match_actions" as permissive for select to authenticated using (true);

create policy "Users can insert own match actions"
  on "public"."match_actions" as permissive for insert to authenticated
  with check (auth.uid() = player_id);


-- Both-submitted handshake: when the second player's action for the
-- current turn lands, bump matches.current_turn. SECURITY DEFINER so the
-- trigger updates matches regardless of the inserter's RLS qualifying.
-- The `current_turn = NEW.turn_number` guard makes it a no-op if a late
-- duplicate insert arrives after the turn has already advanced.

create or replace function public.advance_turn_on_both_submitted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  submitted int;
begin
  select count(distinct player_id) into submitted
    from public.match_actions
    where match_id = NEW.match_id and turn_number = NEW.turn_number;

  if submitted >= 2 then
    update public.matches
      set current_turn = current_turn + 1, updated_at = now()
      where id = NEW.match_id and current_turn = NEW.turn_number;
  end if;
  return NEW;
end;
$$;

CREATE TRIGGER trg_advance_turn_on_both_submitted
  AFTER INSERT ON public.match_actions
  FOR EACH ROW EXECUTE FUNCTION public.advance_turn_on_both_submitted();

CREATE TRIGGER on_matches_updated
  BEFORE UPDATE ON public.matches
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- Realtime: clients subscribe to postgres_changes on these tables to
-- observe opponent submissions and turn advancement. The `supabase_realtime`
-- publication is created by Supabase's services (not by plain Postgres), so
-- we guard the attach — CI runs migrations against a vanilla Postgres where
-- the publication doesn't exist yet, and we don't want this to break the
-- migration-replays-cleanly check.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.matches;
    alter publication supabase_realtime add table public.match_actions;
  end if;
end $$;
