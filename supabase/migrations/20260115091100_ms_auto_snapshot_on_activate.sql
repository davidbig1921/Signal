-- =============================================================================
-- Migration: ms_auto_snapshot_on_activate
-- Purpose:
--   - Ensure activating a decision logic version auto-takes a deploy snapshot
--   - Idempotent + reset-safe
-- =============================================================================

begin;

-- Only create the trigger if the table AND trigger function exist.
do $$
begin
  if to_regclass('public.ms_decision_logic_version') is not null
     and to_regprocedure('public.ms_on_decision_logic_activated()') is not null then

    -- Create trigger only if missing
    if not exists (
      select 1
      from pg_trigger
      where tgname = 'trg_ms_snapshot_on_activate'
    ) then
      create trigger trg_ms_snapshot_on_activate
      after update of is_active on public.ms_decision_logic_version
      for each row
      when (new.is_active is true and (old.is_active is distinct from new.is_active))
      execute function public.ms_on_decision_logic_activated();
    end if;

  end if;
end
$$;

commit;
