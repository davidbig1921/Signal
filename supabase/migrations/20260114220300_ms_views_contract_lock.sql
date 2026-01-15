-- =============================================================================
-- Mercy Signal
-- Migration: ms_views_contract_lock
-- Purpose:
--   - Rebuild v_production_decisions + v_production_decisions_explain safely
--   - Drop in correct dependency order
--   - Explicit column lists (no d.* surprises)
--   - No duplicate columns (fixes "specified more than once")
-- =============================================================================

begin;

-- Drop dependent view first
drop view if exists public.v_production_decisions_explain;
drop view if exists public.v_production_decisions;

create view public.v_production_decisions as
with prod as (
  select
    e.signal_id,
    e.created_at,
    e.is_production_issue,
    e.production_issue_score,
    case
      when e.created_at >= (now() - interval '24 hours') then 1.0
      when e.created_at >= (now() - interval '3 days')  then 0.7
      when e.created_at >= (now() - interval '7 days')  then 0.4
      else 0.1
    end as recency_weight
  from public.v_signal_entries_enriched e
),
agg as (
  select
    p.signal_id,
    count(*) filter (where p.is_production_issue and p.created_at >= (now() - interval '24 hours'))::integer as prod_issues_24h,
    count(*) filter (where p.is_production_issue and p.created_at >= (now() - interval '7 days'))::integer as prod_issues_7d,
    max(p.created_at) filter (where p.is_production_issue) as last_prod_issue_at,
    coalesce(
      sum(p.production_issue_score::numeric * p.recency_weight)
        filter (where p.is_production_issue and p.created_at >= (now() - interval '7 days')),
      0::numeric
    )::integer as severity_score_7d
  from prod p
  group by p.signal_id
),
base as (
  select
    a.signal_id,
    a.prod_issues_24h,
    a.prod_issues_7d,
    a.last_prod_issue_at,
    case
      when a.last_prod_issue_at is null then null::numeric
      else extract(epoch from now() - a.last_prod_issue_at) / 60.0
    end as minutes_since_last_prod_issue,
    a.severity_score_7d
  from agg a
),
scored as (
  select
    b.*,
    public.ms_production_status(
      b.prod_issues_24h,
      b.prod_issues_7d,
      b.minutes_since_last_prod_issue,
      b.severity_score_7d
    ) as production_status
  from base b
),
actioned as (
  select
    s.*,
    public.ms_suggested_action_code_normalize(
      case s.production_status
        when 'incident' then 'page_oncall'
        when 'investigate' then 'investigate'
        when 'watch' then 'monitor'
        else 'noop'
      end
    ) as suggested_action_code
  from scored s
)
select
  signal_id,
  prod_issues_24h,
  prod_issues_7d,
  last_prod_issue_at,
  minutes_since_last_prod_issue,
  severity_score_7d,
  production_status,
  suggested_action_code,
  public.ms_suggested_action_text(suggested_action_code) as suggested_action_text
from actioned;

create view public.v_production_decisions_explain as
with d as (
  select
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    production_status,
    suggested_action_code,
    suggested_action_text
  from public.v_production_decisions
),
calc as (
  select
    d.*,
    case
      when d.prod_issues_7d = 0 and d.prod_issues_24h = 0 then 'stable'
      when d.prod_issues_7d = 0 and d.prod_issues_24h > 0 then 'worsening'
      when d.prod_issues_24h >= greatest(d.prod_issues_7d / 7.0, 0.25) * 1.5 then 'worsening'
      when d.prod_issues_24h <= greatest(d.prod_issues_7d / 7.0, 0.25) * 0.67 then 'improving'
      else 'stable'
    end as trend_24h_vs_7d,
    least(100, (d.prod_issues_7d * 6)
      + case d.production_status
          when 'incident' then 25
          when 'investigate' then 15
          when 'watch' then 5
          else 0
        end
    ) as confidence_score
  from d
)
select
  signal_id,
  prod_issues_24h,
  prod_issues_7d,
  last_prod_issue_at,
  minutes_since_last_prod_issue,
  severity_score_7d,
  production_status,
  suggested_action_code,
  suggested_action_text,
  trend_24h_vs_7d,
  case when confidence_score >= 70 then 'high'
       when confidence_score >= 35 then 'medium'
       else 'low'
  end as confidence,
  case when severity_score_7d >= 200 then 'High'
       when severity_score_7d >= 80 then 'Medium'
       when severity_score_7d > 0 then 'Low'
       else 'None'
  end as severity_label,
  case
    when production_status = 'incident' then 'INCIDENT_RECENT_HIGH_SEVERITY'
    when production_status = 'investigate' then 'INVESTIGATE_ELEVATED_7D'
    when production_status = 'watch' then 'WATCH_RECENT_NOT_SPIKING'
    else 'OK_NO_RECENT_PROD_ISSUES'
  end as status_reason_code
from calc;

grant select on public.v_production_decisions to authenticated;
grant select on public.v_production_decisions_explain to authenticated;

commit;
