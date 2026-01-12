begin;

-- =========================================================
-- Production decisions per signal (SQL-driven decision engine)
-- =========================================================

create or replace view public.v_production_decisions as
with prod as (
  select
    e.signal_id,
    e.created_at,
    e.is_production_issue,
    e.production_issue_score,
    -- time-decay weight (recency beats volume)
    case
      when e.created_at >= now() - interval '24 hours' then 1.0
      when e.created_at >= now() - interval '3 days' then 0.7
      when e.created_at >= now() - interval '7 days' then 0.4
      else 0.1
    end as recency_weight
  from public.v_signal_entries_enriched e
),
agg as (
  select
    p.signal_id,

    count(*) filter (
      where p.is_production_issue
        and p.created_at >= now() - interval '24 hours'
    )::int as prod_issues_24h,

    count(*) filter (
      where p.is_production_issue
        and p.created_at >= now() - interval '7 days'
    )::int as prod_issues_7d,

    max(p.created_at) filter (where p.is_production_issue) as last_prod_issue_at,

    coalesce(
      sum(
        (p.production_issue_score::numeric * p.recency_weight)
      ) filter (where p.is_production_issue and p.created_at >= now() - interval '7 days'),
      0
    )::int as severity_score_7d

  from prod p
  group by p.signal_id
)
select
  a.signal_id,
  a.prod_issues_24h,
  a.prod_issues_7d,
  a.last_prod_issue_at,
  case
    when a.last_prod_issue_at is null then null
    else extract(epoch from (now() - a.last_prod_issue_at)) / 60.0
  end as minutes_since_last_prod_issue,
  a.severity_score_7d,
  case
    when a.prod_issues_24h >= 1 then 'incident'
    when a.severity_score_7d >= 60 then 'incident'
    when a.severity_score_7d >= 30 then 'investigate'
    when a.prod_issues_7d >= 3 then 'investigate'
    when a.severity_score_7d >= 10 then 'watch'
    when a.prod_issues_7d >= 1 then 'watch'
    else 'ok'
  end as production_status
from agg a;

commit;
