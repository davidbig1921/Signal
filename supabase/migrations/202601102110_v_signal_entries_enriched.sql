-- ============================================================================
-- File: supabase/migrations/202601102110_v_signal_entries_enriched.sql
-- Version: 202601102110
-- Project: Mercy Signal
-- Purpose:
--   Enriched entries view: base columns + computed production issue flags/score.
--
-- Safety notes:
--   - Uses CREATE OR REPLACE to avoid dropping dependent views.
--   - IMPORTANT: base column ORDER must match the existing production view order.
--     (Postgres cannot reorder columns in CREATE OR REPLACE VIEW.)
--   - No data is modified.
-- ============================================================================

begin;

create or replace view public.v_signal_entries_enriched as
select
  -- base columns (MUST match existing prod view order)
  e.id,
  e.signal_id,
  e.body,
  e.source,
  e.kind,
  e.severity,
  e.area,
  e.created_at,
  e.created_by,

  -- computed columns (safe to append)
  public.is_production_issue(e)      as is_production_issue,
  public.production_issue_score(e)   as production_issue_score,
  public.production_issue_reason(e)  as production_issue_reason
from public.signal_entries e;

commit;
