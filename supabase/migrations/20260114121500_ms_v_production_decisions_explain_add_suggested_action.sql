-- =============================================================================
-- Mercy Signal
-- Migration: ms_v_production_decisions_explain_add_suggested_action
-- Purpose:
--   - Rebuild v_production_decisions_explain
--   - Add trend/confidence/severity/status_reason_code
--   - Include suggested_action_code/text exactly once (already in base view)
-- Notes:
--   - Use DROP + CREATE to avoid "cannot drop columns from view" issues
--   - Use explicit column list to avoid duplicates and ordering surprises
-- =============================================================================

begin;

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

    -- already locked contract (present in v_production_decisions)
    d.suggested_action_code,
    d.suggested_action_text,

    -- Trend: compare 24h to 7d baseline (rate-ish)
    case
      when coalesce(d.prod_issues_7d, 0) = 0 and coalesce(d.prod_issues_24h, 0) = 0 then 'stable'
      when coalesce(d.prod_issues_7d, 0) = 0 and coalesce(d.prod_issues_24h, 0) > 0 then 'worsening'
      when d.prod_issues_24h >= (d.prod_issues_7d / 7.0) * 1.5 then 'worsening'
      when d.prod_issues_24h <= (d.prod_issues_7d / 7.0) * 0.5 then 'improving'
      else 'stable'
    end as trend_label

  from public.v_production_decisions d
),
calc as (
  select
    b.*,

    -- Confidence label (simple + deterministic)
    case
      when b.production_status = 'incident' then 'high'
      when coalesce(b.prod_issues_7d, 0) >= 10 then 'high'
      when coalesce(b.prod_issues_7d, 0) >= 3 then 'medium'
      else 'low'
    end as confidence_label,

    -- Severity label (aligned with UI fallback thresholds)
    case
      when b.severity_score_7d >= 200 then 'High'
      when b.severity_score_7d >= 80 then 'Medium'
      when b.severity_score_7d > 0 then 'Low'
      else 'None'
    end as severity_label,

    -- Explainability as CODE (no prose)
    case
      when b.production_status = 'incident' then 'INCIDENT_RECENT_24H'
      when b.production_status = 'investigate' then 'INVESTIGATE_ELEVATED_7D'
      when b.production_status = 'watch' and (
        (coalesce(b.prod_issues_7d, 0) = 0 and coalesce(b.prod_issues_24h, 0) > 0)
        or (b.prod_issues_24h >= (b.prod_issues_7d / 7.0) * 1.5)
      ) then 'WATCH_WORSENING'
      when b.production_status = 'watch' then 'WATCH_RECENT_7D'
      else 'OK_NONE_7D'
    end as status_reason_code

  from base b
)
select
  c.*
from calc c;

grant select on public.v_production_decisions_explain to authenticated;

commit;
