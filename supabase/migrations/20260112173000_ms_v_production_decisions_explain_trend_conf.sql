-- ============================================================================
-- File: supabase/migrations/20260112173000_ms_v_production_decisions_explain_trend_conf.sql
-- Version: 20260112-01
-- Project: Mercy Signal
-- Purpose:
--   Add trend + confidence to v_production_decisions_explain (deterministic).
-- Notes:
--   - DROP+CREATE avoids view replace issues.
--   - Depends on: public.v_production_decisions
-- ============================================================================

begin;

drop view if exists public.v_production_decisions_explain;

create view public.v_production_decisions_explain as
with base as (
  select
    d.*,

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
  b.*,

  case
    when b.production_status = 'incident' then 'high'
    when coalesce(b.prod_issues_7d, 0) >= 10 then 'high'
    when coalesce(b.prod_issues_7d, 0) >= 3 then 'medium'
    else 'low'
  end as confidence,

  -- Severity bins (score-only; for explain/debug)
  case
    when b.severity_score_7d >= 80 then 3
    when b.severity_score_7d >= 40 then 2
    when b.severity_score_7d >= 15 then 1
    else 0
  end as severity_level_score,

  case
    when b.severity_score_7d >= 80 then 'High'
    when b.severity_score_7d >= 40 then 'Medium'
    when b.severity_score_7d >= 15 then 'Low'
    else 'None'
  end as severity_label_score,

  -- Severity (final): status floor + score
  greatest(
    case
      when b.production_status = 'incident' then 3
      when b.production_status = 'investigate' then 2
      when b.production_status = 'watch' then 1
      else 0
    end,
    case
      when b.severity_score_7d >= 80 then 3
      when b.severity_score_7d >= 40 then 2
      when b.severity_score_7d >= 15 then 1
      else 0
    end
  ) as severity_level,

  case greatest(
    case
      when b.production_status = 'incident' then 3
      when b.production_status = 'investigate' then 2
      when b.production_status = 'watch' then 1
      else 0
    end,
    case
      when b.severity_score_7d >= 80 then 3
      when b.severity_score_7d >= 40 then 2
      when b.severity_score_7d >= 15 then 1
      else 0
    end
  )
    when 3 then 'High'
    when 2 then 'Medium'
    when 1 then 'Low'
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

commit;
