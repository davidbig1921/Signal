-- ============================================================================
-- File: supabase/migrations/20260116101500_ms_decision_quality_audit.sql
-- Project: Mercy Signal
-- Purpose:
--   Add a lightweight audit view to inspect decision quality distribution:
--   status + severity + counts + recency + explainability fields (when present).
-- Notes:
--   - Does NOT change existing decision logic.
--   - Uses v_production_decisions_explain if available, falls back to base view.
--   - Safe to deploy repeatedly (CREATE OR REPLACE).
-- ============================================================================

begin;

create or replace view public.v_ms_decision_quality_audit as
with explain as (
  select
    signal_id,
    production_status,
    severity_score_7d,
    prod_issues_24h,
    prod_issues_7d,
    minutes_since_last_prod_issue,
    last_prod_issue_at,
    suggested_action_code,
    suggested_action_text,
    trend_24h_vs_7d,
    confidence,
    severity_label,
    status_reason_code,
    true as using_explain
  from public.v_production_decisions_explain
),
base as (
  select
    signal_id,
    production_status,
    severity_score_7d,
    prod_issues_24h,
    prod_issues_7d,
    minutes_since_last_prod_issue,
    last_prod_issue_at,
    suggested_action_code,
    suggested_action_text,
    null::text as trend_24h_vs_7d,
    null::text as confidence,
    null::text as severity_label,
    null::text as status_reason_code,
    false as using_explain
  from public.v_production_decisions
)
select *
from explain
union all
select *
from base
where not exists (select 1 from explain);

comment on view public.v_ms_decision_quality_audit is
'QA view: distribution of decisions and explainability fields. Uses explain view when available.';

commit;
