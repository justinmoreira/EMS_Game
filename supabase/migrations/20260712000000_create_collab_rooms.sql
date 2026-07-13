-- Collaborative sandbox rooms: two players share ONE live sandbox with full
-- shared control (either can place/move/edit/delete any unit). Unlike a 1v1
-- match, there is no turn structure, no fog, and no win condition — it's an
-- open, jointly-edited scene.
--
-- Transport split (mirrors nothing in matches, so it lives here):
--   * Live edits sync peer-to-peer over a Realtime BROADCAST channel as
--     per-unit ops (upsert/delete by a stable unit uid, last-writer-wins).
--     Those never touch the database — broadcast is ephemeral by design.
--   * `state_json` is the DURABLE shared snapshot: a participant periodically
--     upserts the merged board here so a reload or a late joiner can restore
--     the room, and so it can be copied into a normal sandbox slot afterwards.
--
-- Lobby semantics (create / join-by-code / public browse / private) mirror
-- `matches` post-`enforce_private_lobbies`, so the RLS is written tight from
-- the start rather than loosened-then-hardened across migrations.


  create table "public"."collab_rooms" (
    "id" text not null,
    "name" text not null default 'Sandbox'::text,
    "host_id" uuid,
    "guest_id" uuid,
    "seed" bigint not null,
    "visibility" text not null default 'public'::text,
    "invite_code" text,
    "status" text not null default 'waiting'::text,
    "state_json" jsonb not null default '{"units": [], "extra": {}}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."collab_rooms" enable row level security;

CREATE UNIQUE INDEX collab_rooms_pkey ON public.collab_rooms USING btree (id);

alter table "public"."collab_rooms" add constraint "collab_rooms_pkey" PRIMARY KEY using index "collab_rooms_pkey";

-- Unique invite code, but only among rows that have one (private rooms).
CREATE UNIQUE INDEX collab_rooms_invite_code_key ON public.collab_rooms USING btree (invite_code)
  WHERE invite_code IS NOT NULL;

-- Hot path for the lobby browser: open public rooms, newest first.
CREATE INDEX collab_rooms_browse_idx ON public.collab_rooms USING btree (visibility, status, created_at DESC);

alter table "public"."collab_rooms" add constraint "collab_rooms_host_id_fkey"
  FOREIGN KEY (host_id) REFERENCES auth.users(id) ON DELETE SET NULL;

alter table "public"."collab_rooms" add constraint "collab_rooms_guest_id_fkey"
  FOREIGN KEY (guest_id) REFERENCES auth.users(id) ON DELETE SET NULL;


-- RLS. Private rooms are visible only to their participants (and their invite
-- code stays hidden with them); public rooms are browsable by anyone signed in.
-- Null visibility is treated as public for forward-compat, matching matches.

create policy "Read public or participating collab rooms"
  on "public"."collab_rooms" as permissive for select to authenticated
  using (
    visibility is distinct from 'private'
    or auth.uid() = host_id
    or auth.uid() = guest_id
  );

create policy "Users can create own collab rooms"
  on "public"."collab_rooms" as permissive for insert to authenticated
  with check (auth.uid() = host_id);

-- Either participant may update the room (state_json persistence, name, etc.).
-- Joining does NOT go through this policy — it uses join_collab() below, so we
-- don't need a guest_id-is-null self-join branch here (that was the private
-- lobby hole in matches).
create policy "Participants can update collab rooms"
  on "public"."collab_rooms" as permissive for update to authenticated
  using (auth.uid() = host_id or auth.uid() = guest_id);

create policy "Hosts can delete their collab rooms"
  on "public"."collab_rooms" as permissive for delete to authenticated
  using (auth.uid() = host_id);


-- Auto-activate: when the guest seat is filled on a waiting room, flip to
-- 'active' without a client round-trip (mirrors activate_match_on_guest_join).
create or replace function public.activate_collab_on_guest_join()
returns trigger
language plpgsql
as $$
begin
  if NEW.guest_id is not null and OLD.guest_id is null and NEW.status = 'waiting' then
    NEW.status := 'active';
  end if;
  return NEW;
end;
$$;

CREATE TRIGGER trg_activate_collab_on_guest_join
  BEFORE UPDATE ON public.collab_rooms
  FOR EACH ROW EXECUTE FUNCTION public.activate_collab_on_guest_join();

CREATE TRIGGER on_collab_rooms_updated
  BEFORE UPDATE ON public.collab_rooms
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- Claim the guest seat on a waiting room by its id OR invite code. SECURITY
-- DEFINER so it can reach a private room the caller can't SELECT under the
-- tightened read policy — knowing the id/code is the entry ticket. Atomic
-- single UPDATE (no read-modify-write race). Returns the room id, or raises
-- if there's no open seat. Mirrors join_match.
create or replace function public.join_collab(p_id_or_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  r_id text;
begin
  update public.collab_rooms
    set guest_id = auth.uid()
    where (id = p_id_or_code or invite_code = p_id_or_code)
      and guest_id is null
      and host_id <> auth.uid()
    returning id into r_id;
  if r_id is null then
    -- Either the room is full/gone, or the caller is already the host. If the
    -- caller already participates, treat it as a no-op success so re-opening a
    -- link they own doesn't error.
    select id into r_id
      from public.collab_rooms
      where (id = p_id_or_code or invite_code = p_id_or_code)
        and (host_id = auth.uid() or guest_id = auth.uid());
    if r_id is null then
      raise exception 'No open collab room for that code';
    end if;
  end if;
  return r_id;
end;
$$;

grant execute on function public.join_collab(text) to authenticated;


-- Realtime: clients subscribe to postgres_changes on collab_rooms to observe
-- the guest joining (waiting -> active), name changes, and durable state_json
-- snapshots. Live per-unit edits ride a separate broadcast channel, not this.
-- REPLICA IDENTITY FULL so UPDATE events carry enough of the row for Realtime
-- to evaluate RLS (without it, UPDATE broadcasts are silently dropped — the
-- exact bug fixed for matches in realtime_replica_identity).
alter table "public"."collab_rooms" replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.collab_rooms;
  end if;
end $$;
