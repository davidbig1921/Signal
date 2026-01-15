-- =============================================================================
-- Migration: ms_v_production_decisions_explain_align
-- Purpose:
--   - Rebuild v_production_decisions_explain aligned with v_production_decisions
--   - Keep UI column names for non-wording fields:
--       trend_24h_vs_7d, confidence, severity_label
--   - Explainability as CODES (no prose), reuse suggested_action contract
-- =============================================================================

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
with base as (
  select
    d.*,

    -- baseline (rate-ish)
    greatest(d.prod_issues_7d / 7.0, 0.25) as baseline_daily,

    case
      when d.prod_issues_7d = 0 then null
      else d.prod_issues_24h / greatest(d.prod_issues_7d / 7.0, 0.25)
    end as trend_ratio
  from public.v_production_decisions d
),
calc as (
  select
    b.*,

    -- trend label that matches the tuned thresholds
    case
      when b.trend_ratio is null then 'stable'
      when b.trend_ratio >= 2.0 then 'worsening'
      when b.trend_ratio <= 0.67 then 'improving'
      else 'stable'
    end as trend_24h_vs_7d,

    -- confidence score (simple + monotonic)
    least(
      100,
      (greatest(b.prod_issues_7d, 0) * 6)
      + case b.production_status
          when 'incident' then 25
          when 'investigate' then 15
          when 'watch' then 5
          else 0
        end
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
    when c.confidence_score >= 70 then 'high'
    when c.confidence_score >= 35 then 'medium'
    else 'low'
  end as confidence,

  case
    when c.severity_score_7d >= 200 then 'High'
    when c.severity_score_7d >= 80 then 'Medium'
    when c.severity_score_7d > 0 then 'Low'
    else 'None'
  end as severity_label,

  -- Explainability as CODE (no prose)
  case
    when c.production_status = 'incident'
      then 'INCIDENT_RECENT_HIGH_SEVERITY'
    when c.production_status = 'investigate' and c.trend_24h_vs_7d = 'worsening'
      then 'INVESTIGATE_WORSENING_VS_BASELINE'
    when c.production_status = 'investigate'
      then 'INVESTIGATE_ELEVATED_RISK'
    when c.production_status = 'watch'
      then 'WATCH_RECENT_NOT_SPIKING'
    else 'OK_NO_RECENT_PROD_ISSUES'
  end as status_reason_code,

  -- Reuse deterministic action contract from base view
  c.suggested_action_code,
  c.suggested_action_text

from calc c;
