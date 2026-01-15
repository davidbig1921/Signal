-- =============================================================================
-- Migration: ms_active_logic_version_view
-- Purpose:
--   - Provide a stable "active decision logic version" view for the UI
--   - Reset-safe: drop + create (no OR REPLACE)
-- =============================================================================

begin;

drop view if exists public.v_active_decision_logic_version cascade;

create view public.v_active_decision_logic_version as
select
  v.id as decision_version_id,
  v.description as decision_version_description
from public.ms_decision_logic_version v
where v.is_active = true
order by v.id desc
limit 1;

comment on view public.v_active_decision_logic_version is
'Returns the single active decision logic version (id + description).';

commit;
