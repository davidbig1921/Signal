begin;

create or replace function public.ms_auto_snapshot_on_logic_activate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active = true and old.is_active = false then
    -- idempotent: unique index on ms_deploy_snapshot.logic_version_id prevents duplicates
    perform public.ms_take_deploy_snapshot(
      'activate_logic',
      null,
      'logic_version=' || new.id
    );

    -- attach logic version id to the latest snapshot if not already set
    update public.ms_deploy_snapshot
      set logic_version_id = new.id
    where id = (
      select max(id) from public.ms_deploy_snapshot
      where logic_version_id is null
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ms_snapshot_on_activate
on public.ms_decision_logic_version;

create trigger trg_ms_snapshot_on_activate
after update of is_active on public.ms_decision_logic_version
for each row
execute function public.ms_auto_snapshot_on_logic_activate();

commit;
