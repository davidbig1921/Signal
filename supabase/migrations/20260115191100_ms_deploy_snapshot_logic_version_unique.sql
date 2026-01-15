begin;

alter table public.ms_deploy_snapshot
add column if not exists logic_version_id text;

create unique index if not exists ms_deploy_snapshot_unique_logic_version
on public.ms_deploy_snapshot (logic_version_id)
where logic_version_id is not null;

commit;
