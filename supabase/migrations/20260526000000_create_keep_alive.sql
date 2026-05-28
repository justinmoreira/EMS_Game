create table public.keep_alive (
  id int primary key,
  last_ping timestamptz not null default now()
);

insert into public.keep_alive (id) values (1);

-- RLS enabled with no policies: only direct DB connections (postgres role)
-- and service_role can touch this table. The keep-alive workflow uses the
-- DB URL secret, so anon clients have no access.
alter table public.keep_alive enable row level security;
