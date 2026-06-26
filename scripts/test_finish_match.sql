-- Integration test for finish_match(): participant guard, idempotency, and
-- leaderboard tallies. Runs in a transaction and ROLLs BACK, so it leaves the
-- local DB untouched. Run via:
--   docker exec -i <supabase_db> psql -U postgres -f - < scripts/test_finish_match.sql
\set ON_ERROR_STOP on
begin;

-- Two real auth users (profiles auto-create via the on_auth_user_created trigger).
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'host@test.local', now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'guest@test.local', now(), now());

insert into public.matches (id, seed, host_id, guest_id, status, name)
values ('TESTMATCH', 123, '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222', 'active', 'Test');

-- Act as the host (auth.uid() reads request.jwt.claims.sub).
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

select public.finish_match('TESTMATCH', '11111111-1111-1111-1111-111111111111');
-- Idempotent: a second call (e.g. the other client) must not double-count.
select public.finish_match('TESTMATCH', '11111111-1111-1111-1111-111111111111');

\echo '--- match (expect finished + winner=host) ---'
select status, winner_id from public.matches where id = 'TESTMATCH';

\echo '--- match_results (expect 1 row, winner=host, loser=guest) ---'
select winner_id, loser_id, is_draw from public.match_results where match_id = 'TESTMATCH';

\echo '--- profiles (expect host 1/0, guest 0/1, games_played 1 each) ---'
select id, wins, losses, draws, games_played
from public.profiles
where id in ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222')
order by id;

rollback;
