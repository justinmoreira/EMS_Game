-- Enforce private lobbies at the data layer (bug_002).
--
-- Before: matches.SELECT was `using (true)` — any authenticated user could read
-- every lobby row, including private ones AND their invite_code — and the UPDATE
-- policy allowed `guest_id is null`, letting anyone claim the empty guest seat on
-- any waiting match without knowing the code. So "private" was cosmetic.
--
-- Fix:
--   1. SELECT: private rows are visible only to their participants; everything
--      not-private stays publicly readable (null visibility is treated as public
--      for back-compat).
--   2. UPDATE: drop the `guest_id is null` self-join branch — only the two
--      participants may update a match.
--   3. Joining now goes through join_match(), a SECURITY DEFINER RPC that can
--      reach a private lobby the caller cannot SELECT, and only ever fills an
--      empty guest seat on a match the caller does not already host.

drop policy if exists "Authenticated users can read matches" on "public"."matches";
create policy "Read public or participating matches"
  on "public"."matches" as permissive for select to authenticated
  using (
    visibility is distinct from 'private'
    or auth.uid() = host_id
    or auth.uid() = guest_id
  );

drop policy if exists "Participants can update matches" on "public"."matches";
create policy "Participants can update matches"
  on "public"."matches" as permissive for update to authenticated
  using (auth.uid() = host_id or auth.uid() = guest_id);

-- Claim the guest seat on a waiting lobby by its id OR invite code. SECURITY
-- DEFINER so it can locate a private lobby the caller can't read under the
-- tightened SELECT policy. Knowing the id/code is the entry ticket (consistent
-- with the "share the invite code or link" UX). Returns the match id so the
-- client can navigate into it.
create or replace function public.join_match(p_id_or_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  m_id text;
begin
  update public.matches
    set guest_id = auth.uid()
    where (id = p_id_or_code or invite_code = p_id_or_code)
      and guest_id is null
      and host_id <> auth.uid()
    returning id into m_id;
  if m_id is null then
    raise exception 'No open lobby for that code';
  end if;
  return m_id;
end;
$$;

grant execute on function public.join_match(text) to authenticated;
