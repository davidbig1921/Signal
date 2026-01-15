begin;

-- Trigger function
create or replace function public.ms_auto_snapshot_on_logic_activate()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Only fire when a version is ACTIVATED
  if new.is_active = true and old.is_active = false then
    perform public.ms_snapshot_current_decisions();
  end if;

  return new;
end;
$$;

-- Trigger
drop trigger if exists trg_ms_snapshot_on_activate
on public.ms_decision_logic_version;

create trigger trg_ms_snapshot_on_activate
after update on public.ms_decision_logic_version
for each row
execute function public.ms_auto_snapshot_on_logic_activate();

commit;
