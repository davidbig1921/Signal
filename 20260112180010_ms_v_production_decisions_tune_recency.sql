-- =============================================================================
-- Migration: ms_v_production_decisions_tune_recency
-- Purpose:
--   - Rebuild v_production_decisions deterministically
--   - Avoid column-rename conflicts by drop+recreate
--   - Handle dependent views (v_production_decisions_explain)
--   - Keep stable contract + allow later migrations to tune explain view
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Drop dependent views first (so base can be dropped cleanly)
-- -----------------------------------------------------------------------------
drop view if exists public.v_production_decisions_explain;

drop view if exists public.v_production_decisions;

-- -----------------------------------------------------------------------------
-- Recreate base view
-- -----------------------------------------------------------------------------
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

  public.ms_production_status(
    b.prod_issues_24h,
    b.prod_issues_7d,
    b.minutes_since_last_prod_issue,
    b.severity_score_7d
  ) as production_status,

  -- legacy column kept for historical compatibility
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
  end as status_reason,

  -- modern append-only columns
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

  public.ms_suggested_action_text_safe(
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

-- -----------------------------------------------------------------------------
-- Recreate an explain view stub (later migrations can replace/tune it)
-- -----------------------------------------------------------------------------
create view public.v_production_decisions_explain as
select
  d.signal_id,
  d.prod_issues_24h,
  d.prod_issues_7d,
  d.last_prod_issue_at,
  d.minutes_since_last_prod_issue,
  d.severity_score_7d,
  d.production_status,

  -- keep modern contract columns if present in base
  d.suggested_action_code,
  d.suggested_action_text,

  -- explain-only columns as safe defaults
  'stable'::text as trend_24h_vs_7d,
  'low'::text as confidence,
  case
    when coalesce(d.severity_score_7d, 0) >= 200 then 'High'
    when coalesce(d.severity_score_7d, 0) >= 80 then 'Medium'
    when coalesce(d.severity_score_7d, 0) > 0 then 'Low'
    else 'None'
  end as severity_label,
  null::text as status_reason_code
from public.v_production_decisions d;

commit;
