-- =============================================================================
-- Mercy Signal
-- Migration: ms_v_production_decisions_explain_tune
-- Purpose:
--   Tune trend + confidence + reasons/hints based on 24h vs 7d and volume.
-- =============================================================================

create or replace view v_production_decisions_explain as
with base as (
  select
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    production_status
  from v_production_decisions
),
calc as (
  select
    b.*,

    -- Trend: compare 24h*7 vs 7d (rate change)
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
    end as trend_label,

    -- Confidence score (numeric), then label
    (
      ln(1 + greatest(b.prod_issues_7d, 0)) +
      case when b.prod_issues_24h >= 1 then 0.8 else 0 end +
      case when b.production_status in ('incident','investigate') then 0.7 else 0 end
    ) as confidence_score
  from base b
),
final as (
  select
    c.*,

    case
      when c.confidence_score >= 3.0 then 'high'
      when c.confidence_score >= 2.0 then 'medium'
      else 'low'
    end as confidence_label,

    -- Severity label derived from score (keep stable even if UI fallback exists)
    case
      when c.severity_score_7d >= 200 then 'High'
      when c.severity_score_7d >= 80 then 'Medium'
      when c.severity_score_7d > 0 then 'Low'
      else 'None'
    end as severity_label,

    -- Reasons: deterministic, short, explainable
    case
      when c.production_status = 'incident'
        then 'High severity with recent production issues.'
      when c.production_status = 'investigate'
        then 'Elevated severity; verify recent changes and error clusters.'
      when c.production_status = 'watch'
        then 'Notable production activity; monitor for escalation.'
      else 'No meaningful production issues detected recently.'
    end as status_reason,

    -- Action hints: point to next operator step
    case
      when c.production_status = 'incident'
        then 'Page on-call, identify top error signatures, and mitigate.'
      when c.production_status = 'investigate'
        then 'Review deploys, correlate errors by service, and confirm impact.'
      when c.production_status = 'watch'
        then 'Check trend direction and sample recent entries for patterns.'
      else 'No action needed.'
    end as action_hint
  from calc c
)
select * from final;

comment on view v_production_decisions_explain is
'Mercy Signal tuned explain view: trend uses 24h vs 7d rate comparison; confidence uses volume + recency + incident weighting; includes severity_label, status_reason, action_hint.';
