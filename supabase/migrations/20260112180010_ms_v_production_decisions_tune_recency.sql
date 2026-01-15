-- =============================================================================
-- Migration: ms_v_production_decisions_tune_recency
-- Purpose:
--   - Build v_production_decisions from v_signal_entries_enriched
--   - Keep the column list STABLE (no baseline/trend columns exposed)
--   - production_status is computed by ms_production_status(...) so it stays aligned
--   - Append-only: suggested_action_code + suggested_action_text at end (stable contract)
-- =============================================================================

create or replace view public.v_production_decisions as
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

    count(*) filter (
      where p.is_production_issue
        and p.created_at >= (now() - interval '24 hours')
    )::integer as prod_issues_24h,

    count(*) filter (
      where p.is_production_issue
        and p.created_at >= (now() - interval '7 days')
    )::integer as prod_issues_7d,

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
)
select
  b.signal_id,
  b.prod_issues_24h,
  b.prod_issues_7d,
  b.last_prod_issue_at,
  b.minutes_since_last_prod_issue,
  b.severity_score_7d,

  -- Fix: correct argument order (minutes_since_last_prod_issue, then severity_score_7d)
  public.ms_production_status(
    b.prod_issues_24h,
    b.prod_issues_7d,
    b.minutes_since_last_prod_issue,
    b.severity_score_7d
  ) as production_status,

  -- Append-only columns (prevents "cannot drop columns from view" on replace)
  case public.ms_production_status(
    b.prod_issues_24h,
    b.prod_issues_7d,
    b.minutes_since_last_prod_issue,
    b.severity_score_7d
  )
    when 'incident'     then 'page_oncall'
    when 'investigate'  then 'investigate'
    when 'watch'        then 'monitor'
    else 'noop'
  end as suggested_action_code,

  public.ms_suggested_action_text(
    case public.ms_production_status(
      b.prod_issues_24h,
      b.prod_issues_7d,
      b.minutes_since_last_prod_issue,
      b.severity_score_7d
    )
      when 'incident'     then 'page_oncall'
      when 'investigate'  then 'investigate'
      when 'watch'        then 'monitor'
      else 'noop'
    end
  ) as suggested_action_text

from base b;
