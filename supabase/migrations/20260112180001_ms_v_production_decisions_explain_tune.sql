-- =============================================================================
-- Mercy Signal
-- Migration: ms_v_production_decisions_explain_tune
-- Purpose:
--   Final tuned explain view:
--   - Uses stable column names (trend_24h_vs_7d)
--   - Drops + recreates view to avoid OR REPLACE conflicts
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
    d.production_status
  from public.v_production_decisions d
),
calc as (
  select
    b.*,

    -- Trend: compare 24h rate to 7d baseline
    case
      when b.prod_issues_7d = 0 and b.prod_issues_24h = 0 then 'stable'
      when b.prod_issues_7d = 0 and b.prod_issues_24h > 0 then 'worsening'
      when b.prod_issues_24h >= (b.prod_issues_7d / 7.0) * 1.6 then 'worsening'
      when b.prod_issues_24h <= (b.prod_issues_7d / 7.0) * 0.6 then 'improving'
      else 'stable'
    end as trend_24h_vs_7d,

    -- Confidence score
    (
      ln(1 + greatest(b.prod_issues_7d, 0)) +
      case when b.prod_issues_24h >= 1 then 0.8 else 0 end +
      case when b.production_status in ('incident','investigate') then 0.7 else 0 end
    ) as confidence_score
  from base b
)
select
  c.signal_id,
  c.prod_issues_24h,
  c.prod_issues_7d,
  c.last_prod_issue_at,
  c.minutes_since_last_prod_issue,
  c.severity_score_7d,
  c.production_status,

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
    when c.production_status = 'incident'
      then 'High severity with recent production issues.'
    when c.production_status = 'investigate'
      then 'Elevated severity; verify recent changes and error clusters.'
    when c.production_status = 'watch'
      then 'Notable production activity; monitor for escalation.'
    else 'No meaningful production issues detected recently.'
  end as status_reason,

  case
    when c.production_status = 'incident'
      then 'Page on-call, identify top error signatures, and mitigate.'
    when c.production_status = 'investigate'
      then 'Review deploys, correlate errors by service, and confirm impact.'
    when c.production_status = 'watch'
      then 'Check trend direction and sample recent entries for patterns.'
    else 'No action needed.'
  end as action_hint
from calc c;
