-- =============================================================================
-- Migration: ms_v_production_decisions_explain_add_trend_conf
-- Purpose:
--   Create/extend v_production_decisions_explain WITHOUT assuming optional columns
--   exist on v_production_decisions at this point in migration history.
-- =============================================================================

begin;

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
with d as (
  select
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    production_status
  from public.v_production_decisions
),
x as (
  select
    d.*,

    -- Trend: compare 24h to 7d baseline (null-safe)
    case
      when coalesce(d.prod_issues_7d, 0) = 0 and coalesce(d.prod_issues_24h, 0) > 0 then 'worsening'
      when coalesce(d.prod_issues_24h, 0) = 0 and coalesce(d.prod_issues_7d, 0) > 0 then 'improving'
      when coalesce(d.prod_issues_24h, 0) > 0 and (d.prod_issues_24h * 7) > (d.prod_issues_7d * 2) then 'worsening'
      when coalesce(d.prod_issues_7d, 0) > 0 and (d.prod_issues_24h * 7) < (d.prod_issues_7d / 2) then 'improving'
      else 'stable'
    end as trend_24h_vs_7d,

    -- Confidence: simple volume heuristic
    case
      when coalesce(d.prod_issues_7d, 0) >= 20 then 'high'
      when coalesce(d.prod_issues_7d, 0) >= 5 then 'medium'
      else 'low'
    end as confidence,

    -- Severity label fallback based on score
    case
      when coalesce(d.severity_score_7d, 0) >= 200 then 'High'
      when coalesce(d.severity_score_7d, 0) >= 80 then 'Medium'
      when coalesce(d.severity_score_7d, 0) > 0 then 'Low'
      else 'None'
    end as severity_label,

    -- Reason code (placeholder, can be tuned later)
    null::text as status_reason_code

  from d
)
select * from x;

commit;
