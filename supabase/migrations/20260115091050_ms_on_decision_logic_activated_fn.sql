-- ============================================================================
-- Migration: ms_on_decision_logic_activated_fn
-- Purpose:
--   - Provide trigger function used by trg_ms_snapshot_on_activate
--   - Best-effort snapshot call (never blocks activation)
-- Contract:
--   - Calls public.ms_take_deploy_snapshot(text,text,text) if it exists
-- ============================================================================

begin;

create or replace function public.ms_on_decision_logic_activated()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Only react when is_active flips to true
  if new.is_active is true and (old.is_active is distinct from new.is_active) then
    -- Only call snapshotter if present
    if to_regprocedure('public.ms_take_deploy_snapshot(text,text,text)') is not null then
      begin
        perform public.ms_take_deploy_snapshot(
          new.id::text,
          'decision_logic_activate',
          'auto'
        );
      exception
        when others then
          -- Never block activation due to snapshot issues
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
