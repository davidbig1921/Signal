-- ============================================================================
-- File: supabase/migrations/20260112161000_ms_v_production_decisions_explain.sql
-- Version: 20260112-01
-- Project: Mercy Signal
-- Purpose:
--   Provide explainability + severity labels for Production Decisions.
-- Notes:
--   - DROP+CREATE avoids Postgres CREATE OR REPLACE view column rename issues.
--   - Depends on: public.v_production_decisions
-- ============================================================================

begin;

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
select
  d.*,

  -- Severity bins (deterministic, documented thresholds)
  case
    when d.severity_score_7d >= 80 then 3
    when d.severity_score_7d >= 40 then 2
    when d.severity_score_7d >= 15 then 1
    else 0
  end as severity_level,

  case
    when d.severity_score_7d >= 80 then 'High'
    when d.severity_score_7d >= 40 then 'Medium'
    when d.severity_score_7d >= 15 then 'Low'
    else 'None'
  end as severity_label,

  -- Why (tight, human)
  case
    when d.production_status = 'incident' then
      'Production issues are happening right now.'
    when d.production_status = 'investigate' then
      'Recent production issues suggest elevated risk.'
    when d.production_status = 'watch' then
      'No active issues, but recent history warrants attention.'
    else
      'No production issues detected recently.'
  end as status_reason,

  -- Next action (tight, human)
  case
    when d.production_status = 'incident' then
      'Triage now. Check latest deploy/config. Mitigate (rollback/flag/scale).'
    when d.production_status = 'investigate' then
      'Review recent changes and errors. Assess impact. Fix now or monitor.'
    when d.production_status = 'watch' then
      'Monitor trends. Escalate if new issues. Follow up if repeated.'
    else
      'No action needed. Continue monitoring.'
  end as action_hint

from public.v_production_decisions d;

commit;
