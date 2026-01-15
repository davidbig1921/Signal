-- =============================================================================
-- Migration: ms_v_production_decisions_explain_trend_conf
-- Purpose:
--   Add trend + confidence to v_production_decisions_explain WITHOUT using d.*
--   or b.* (prevents duplicate-column errors across iterations).
-- =============================================================================

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
with base as (
  select
    d.signal_id,
    d.prod_issues_24h,
    d.prod_issues_7d,
    d.last_prod_issue_at,
    d.minutes_since_last_prod_issue,
    d.severity_score_7d,
    d.production_status,

    case
      when coalesce(d.prod_issues_7d, 0) = 0 and coalesce(d.prod_issues_24h, 0) = 0 then 'stable'
      when coalesce(d.prod_issues_7d, 0) = 0 and coalesce(d.prod_issues_24h, 0) > 0 then 'worsening'
      when d.prod_issues_24h >= (d.prod_issues_7d / 7.0) * 1.5 then 'worsening'
      when d.prod_issues_24h <= (d.prod_issues_7d / 7.0) * 0.5 then 'improving'
      else 'stable'
    end as trend_24h_vs_7d
  from public.v_production_decisions d
)
select
  b.signal_id,
  b.prod_issues_24h,
  b.prod_issues_7d,
  b.last_prod_issue_at,
  b.minutes_since_last_prod_issue,
  b.severity_score_7d,
  b.production_status,

  b.trend_24h_vs_7d,

  case
    when b.production_status = 'incident' then 'high'
    when coalesce(b.prod_issues_7d, 0) >= 10 then 'high'
    when coalesce(b.prod_issues_7d, 0) >= 3 then 'medium'
    else 'low'
  end as confidence,

  -- Keep UI-friendly severity label (your UI expects severity_label)
  case
    when b.severity_score_7d >= 200 then 'High'
    when b.severity_score_7d >= 80 then 'Medium'
    when b.severity_score_7d > 0 then 'Low'
    else 'None'
  end as severity_label,

  -- Reason (short)
  case
    when b.production_status = 'incident' then 'Active production issues.'
    when b.production_status = 'investigate' then 'Recent issues raise risk.'
    when b.production_status = 'watch' then 'Quiet now, but keep an eye on it.'
    else 'No recent production issues.'
  end as status_reason,

  -- Next (short, trend-aware)
  case
    when b.production_status = 'incident' then
      'Triage now. Check latest deploy/config. Mitigate (rollback/flag/scale).'
    when b.production_status = 'investigate' then
      case when b.trend_24h_vs_7d = 'worsening'
        then 'Rising risk. Review changes + errors. Decide fix vs monitor.'
        else 'Review recent changes + errors. Decide fix vs monitor.'
      end
    when b.production_status = 'watch' then
      case when b.trend_24h_vs_7d = 'worsening'
        then 'Watch closely. Escalate if it continues.'
        else 'Monitor. Escalate if it returns.'
      end
    else
      'No action. Keep monitoring.'
  end as action_hint
from base b;
