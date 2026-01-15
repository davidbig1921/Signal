-- ============================================================================
-- Mercy Signal
-- Migration: ms_v_production_decisions_explain_fix
-- Purpose:
--   Rebuild v_production_decisions_explain safely (drop + create) so we can
--   change the column set without Postgres "cannot drop columns" errors.
-- ============================================================================

begin;

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
select
  d.*,

  -- deterministic code only
  case
    when d.production_status = 'incident' then 'INCIDENT_RECENT_24H'
    when d.production_status = 'investigate' then 'INVESTIGATE_ELEVATED_7D'
    when d.production_status = 'watch' then 'WATCH_RECENT_7D'
    else 'OK_NONE_7D'
  end as status_reason_code
from public.v_production_decisions d;

grant select on public.v_production_decisions_explain to authenticated;

commit;
