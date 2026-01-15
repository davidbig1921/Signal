-- =============================================================================
-- Migration: ms_v_production_decisions_explain_add_trend_conf
-- Purpose:
--   Rebuild v_production_decisions_explain with stable columns for UI.
--   Uses DROP+CREATE (not CREATE OR REPLACE) to avoid 42P16.
-- =============================================================================

begin;

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
with b as (
  select
    d.signal_id,
    d.prod_issues_24h,
    d.prod_issues_7d,
    d.last_prod_issue_at,
    d.minutes_since_last_prod_issue,
    d.severity_score_7d,
    d.production_status,

    -- include these ONLY if they exist in v_production_decisions today
    d.suggested_action_code,
    d.suggested_action_text
  from public.v_production_decisions d
),
calc as (
  select
    b.*,

    -- Trend: compare 24h rate scaled to 7d vs actual 7d volume
    case
      when (b.prod_issues_7d >= 5 or b.prod_issues_24h >= 2)
       and b.prod_issues_7d > 0
       and (b.prod_issues_24h::numeric * 7) / b.prod_issues_7d >= 1.6
        then 'worsening'
      when (b.prod_issues_7d >= 5 or b.prod_issues_24h >= 2)
       and b.prod_issues_7d > 0
       and (b.prod_issues_24h::numeric * 7) / b.prod_issues_7d <= 0.6
        then 'improving'
      else 'stable'
    end as trend_24h_vs_7d,

    -- Confidence score: volume + recency + status weighting
    (
      ln(1 + greatest(b.prod_issues_7d, 0)) +
      case when b.prod_issues_24h >= 1 then 0.8 else 0 end +
      case when b.production_status in ('incident','investigate') then 0.7 else 0 end
    ) as confidence_score
  from b
)
select
  c.signal_id,
  c.prod_issues_24h,
  c.prod_issues_7d,
  c.last_prod_issue_at,
  c.minutes_since_last_prod_issue,
  c.severity_score_7d,
  c.production_status,

  c.suggested_action_code,
  c.suggested_action_text,

  c.trend_24h_vs_7d,

  case
    when c.confidence_score >= 3.0 then 'high'
    when c.confidence_score >= 2.0 then 'medium'
    else 'low'
  end as confidence,

  case
    when c.severity_score_7d >= 200 then 'High'
    when c.severity_score_7d >= 80 then 'Medium'
    when c.severity_score_7d > 0 then 'Low'
    else 'None'
  end as severity_label,

  case
    when c.production_status = 'incident' then 'INCIDENT_RECENT_HIGH_SEVERITY'
    when c.production_status = 'investigate' then 'INVESTIGATE_ELEVATED_RISK'
    when c.production_status = 'watch' then 'WATCH_RECENT_NOT_SPIKING'
    else 'OK_NO_RECENT_PROD_ISSUES'
  end as status_reason_code

from calc c;

grant select on public.v_production_decisions_explain to authenticated;

commit;
