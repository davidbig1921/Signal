-- ============================================================================
-- File: supabase/migrations/20260116103000_fix_ms_on_decision_logic_activated.sql
-- Project: Mercy Signal
-- Purpose:
--   Restore missing trigger function public.ms_on_decision_logic_activated()
--   used by trg_ms_snapshot_on_activate.
-- Notes:
--   - Idempotent: create or replace.
--   - Best-effort: never blocks activation if snapshot function is unavailable.
-- ============================================================================

begin;

create or replace function public.ms_on_decision_logic_activated()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Only react when is_active flips to true.
  if new.is_active is true and (old.is_active is distinct from new.is_active) then
    -- Take snapshot if the snapshot function exists.
    if to_regprocedure('public.ms_take_deploy_snapshot(text,text,text)') is not null then
      begin
        -- We keep arguments conservative + deterministic.
        -- Adjust names later if you want richer provenance.
        perform public.ms_take_deploy_snapshot(
          new.id::text,
          'decision_logic_activate',
          'auto'
        );
      exception
        when others then
          -- Never block activation due to snapshot failures.
          null;
      end;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.ms_on_decision_logic_activated() is
'Trigger function: when ms_decision_logic_version.is_active flips true, take deploy snapshot (best-effort).';

commit;
