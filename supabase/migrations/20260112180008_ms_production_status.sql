-- =============================================================================
-- Migration: ms_production_status
-- Purpose: Canonical production status classifier used by v_production_decisions
-- Signature:
--   ms_production_status(int, int, numeric, int) -> text
-- =============================================================================

create or replace function public.ms_production_status(
  prod_issues_24h integer,
  prod_issues_7d integer,
  minutes_since_last_prod_issue numeric,
  severity_score_7d integer
)
returns text
language sql
stable
as $$
  with base as (
    select
      greatest(coalesce(prod_issues_24h, 0), 0) as prod_issues_24h,
      greatest(coalesce(prod_issues_7d, 0), 0) as prod_issues_7d,
      minutes_since_last_prod_issue,
      greatest(coalesce(severity_score_7d, 0), 0) as severity_score_7d,
      greatest(greatest(coalesce(prod_issues_7d, 0), 0) / 7.0, 0.25) as baseline_daily,
      case
        when greatest(coalesce(prod_issues_7d, 0), 0) = 0 then null
        else greatest(coalesce(prod_issues_24h, 0), 0) / greatest(greatest(coalesce(prod_issues_7d, 0), 0) / 7.0, 0.25)
      end as trend_ratio
  )
  select
    case
      -- OK if nothing in 7d AND no score
      when prod_issues_7d = 0 and severity_score_7d = 0 then 'ok'

      -- INCIDENT: high severity + recency OR sharp acceleration
      when severity_score_7d >= 200
       and (
         prod_issues_24h >= 1
         or (minutes_since_last_prod_issue is not null and minutes_since_last_prod_issue <= 360) -- 6h
         or (trend_ratio is not null and trend_ratio >= 2.0)
       )
        then 'incident'

      -- INVESTIGATE: elevated vs baseline OR 24h cluster OR meaningful severity
      when (trend_ratio is not null and trend_ratio >= 1.3)
        or prod_issues_24h >= 2
        or severity_score_7d >= 120
        then 'investigate'

      -- WATCH: non-zero 7d / score but not actively spiking
      when prod_issues_7d > 0 or severity_score_7d > 0
        then 'watch'

      else 'ok'
    end
  from base;
$$;
