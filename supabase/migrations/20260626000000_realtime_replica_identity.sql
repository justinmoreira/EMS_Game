-- Supabase Realtime delivers UPDATE/DELETE postgres_changes events to a
-- subscriber only when it can evaluate the table's RLS against the changed
-- row — and that requires the full OLD record in the WAL. With the default
-- replica identity (primary key columns only), matches UPDATEs were silently
-- dropped for subscribers: the host stayed stuck on "waiting for a second
-- player" after the guest joined (status flips waiting→active), and turn-counter
-- bumps could be missed mid-match. REPLICA IDENTITY FULL restores delivery.
alter table public.matches replica identity full;
alter table public.match_actions replica identity full;
