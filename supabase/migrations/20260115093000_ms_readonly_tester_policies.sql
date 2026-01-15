begin;

-- Helper: read app_role from JWT claims
create or replace function public.ms_app_role()
returns text
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'app_role', '');
$$;

-- Ensure views are selectable by authenticated
grant select on public.v_production_decisions to authenticated;
grant select on public.v_production_decisions_explain to authenticated;

-- If you have snapshot tables, allow testers to read them too
-- (optional; comment out if you don't want testers to see snapshots)
grant select on public.ms_deploy_snapshot to authenticated;
grant select on public.ms_deploy_snapshot_production_decisions to authenticated;

-- RLS ON for snapshot tables (views don't use RLS; underlying tables do)
alter table public.ms_deploy_snapshot enable row level security;
alter table public.ms_deploy_snapshot_production_decisions enable row level security;

-- Read-only testers: SELECT only
drop policy if exists ms_tester_read_snapshots on public.ms_deploy_snapshot;
create policy ms_tester_read_snapshots
on public.ms_deploy_snapshot
for select
to authenticated
using (public.ms_app_role() = 'tester');

drop policy if exists ms_tester_read_snapshot_rows on public.ms_deploy_snapshot_production_decisions;
create policy ms_tester_read_snapshot_rows
on public.ms_deploy_snapshot_production_decisions
for select
to authenticated
using (public.ms_app_role() = 'tester');

-- Block all writes for testers (explicitly)
drop policy if exists ms_tester_no_write_snapshots on public.ms_deploy_snapshot;
create policy ms_tester_no_write_snapshots
on public.ms_deploy_snapshot
for all
to authenticated
using (public.ms_app_role() <> 'tester')
with check (public.ms_app_role() <> 'tester');

drop policy if exists ms_tester_no_write_snapshot_rows on public.ms_deploy_snapshot_production_decisions;
create policy ms_tester_no_write_snapshot_rows
on public.ms_deploy_snapshot_production_decisions
for all
to authenticated
using (public.ms_app_role() <> 'tester')
with check (public.ms_app_role() <> 'tester');

commit;
