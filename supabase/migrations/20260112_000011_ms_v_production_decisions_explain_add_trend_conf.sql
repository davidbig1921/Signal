-- =============================================================================
-- Migration: ms_v_production_decisions_explain_add_trend_conf
-- Purpose: add trend_label + confidence_label + reason/hint columns
-- =============================================================================

create or replace view v_production_decisions_explain as
with b as (
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

    -- Trend: compare 24h rate scaled to 7d vs actual 7d volume (avoid noise)
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

    -- Confidence score: volume + recency + incident weighting
    (
      ln(1 + greatest(b.prod_issues_7d, 0)) +
      case when b.prod_issues_24h >= 1 then 0.8 else 0 end +
      case when b.production_status in ('incident','investigate') then 0.7 else 0 end
    ) as confidence_score
  from b
)
select
  c.*,

  case
    when c.confidence_score >= 3.0 then 'high'
    when c.confidence_score >= 2.0 then 'medium'
    else 'low'
  end as confidence_label,

  case
    when c.severity_score_7d >= 200 then 'High'
    when c.severity_score_7d >= 80 then 'Medium'
    when c.severity_score_7d > 0 then 'Low'
    else 'None'
  end as severity_label,

  -- Explainability
  case
    when c.production_status = 'incident'
      then 'High severity with very recent production issues.'
    when c.production_status = 'investigate'
      then 'Elevated risk signal; confirm impact and identify clusters.'
    when c.production_status = 'watch'
      then 'Recent production issues detected, but not actively spiking.'
    else 'No meaningful production issues detected recently.'
  end as status_reason,

  case
    when c.production_status = 'incident'
      then 'Page on-call, identify top signatures, mitigate fastest path.'
    when c.production_status = 'investigate'
      then 'Review deploys + error clusters; confirm scope and rollback need.'
    when c.production_status = 'watch'
      then 'Monitor trend and sample recent entries for repeat patterns.'
    else 'No action needed.'
  end as action_hint
from calc c;

comment on view v_production_decisions_explain is
'Adds trend_label (24h vs 7d rate comparison), confidence_label (volume+recency+status), severity_label, status_reason, action_hint.';
