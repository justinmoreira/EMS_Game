-- Allow a host to delete their own lobby.
--
-- The matches table has RLS enabled with SELECT/INSERT/UPDATE policies but no
-- DELETE policy, so Postgres denies every delete (RLS is default-deny). PostgREST
-- reports that denial as success with 0 rows affected, so the lobby browser's
-- optimistic delete LOOKS like it worked while the row actually survives — the
-- lobby reappears on reload and stays visible/joinable to other players.
--
-- Add the missing DELETE policy, scoped to the host (consistent with the INSERT
-- policy's `auth.uid() = host_id` check). match_actions / match_results cascade
-- via their FKs, so deleting the match cleans up its children.

create policy "Hosts can delete their matches"
  on "public"."matches" as permissive for delete to authenticated
  using (auth.uid() = host_id);
