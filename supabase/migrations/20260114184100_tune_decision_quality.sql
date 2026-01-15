create or replace view public.v_production_decisions_explain as
with base as (
  select
    d.*,

    -- Baseline daily rate (noise-resistant, prevents divide-by-zero and overreacting at low volume)
    greatest(d.prod_issues_7d / 7.0, 0.25) as baseline_daily,

    -- Ratio for trend (24h vs 7d daily baseline)
    case
      when d.prod_issues_7d = 0 then null
      else d.prod_issues_24h / greatest(d.prod_issues_7d / 7.0, 0.25)
    end as trend_ratio
  from public.v_production_decisions d
),
scored as (
  select
    b.*,

    -- Trend label (null-safe)
    case
      when b.trend_ratio is null then 'stable'
      when b.trend_ratio >= 1.5 then 'worsening'
      when b.trend_ratio <= 0.67 then 'improving'
      else 'stable'
    end as trend_label,

    -- Confidence score (0–100): volume + status weighting
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
  s.*,

  -- Confidence label
  case
    when s.confidence_score >= 70 then 'high'
    when s.confidence_score >= 35 then 'medium'
    else 'low'
  end as confidence_label,

  -- Severity label (kept stable for UI + human scanning)
  case
    when s.severity_score_7d >= 200 then 'High'
    when s.severity_score_7d >= 80 then 'Medium'
    when s.severity_score_7d > 0 then 'Low'
    else 'None'
  end as severity_label,

  -- Status reason (human-readable, deterministic)
  case
    when s.production_status = 'incident'
      then 'Multiple recent production issues detected.'
    when s.production_status = 'investigate' and s.prod_issues_24h = 0
      then 'Elevated 7d severity, but no 24h spike.'
    when s.trend_label = 'worsening'
      then 'Issue rate accelerating compared to baseline.'
    when s.prod_issues_7d > 0
      then 'Ongoing but stable production issues.'
    else
      'No meaningful production risk detected.'
  end as status_reason,

  -- Action hint
  case
    when s.production_status = 'incident'
      then 'Page on-call and begin incident response.'
    when s.production_status = 'investigate'
      then 'Review deploys and clusters; confirm impact and scope.'
    when s.production_status = 'watch'
      then 'Monitor closely for escalation.'
    else
      'No action required.'
  end as action_hint

from scored s;

comment on view public.v_production_decisions_explain is
'Adds trend_label (24h vs 7d baseline), confidence_score/label (volume+status), severity_label, status_reason, action_hint for explainable decisions.';
