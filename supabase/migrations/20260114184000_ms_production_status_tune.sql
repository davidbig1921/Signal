-- =============================================================================
-- Migration: ms_production_status_tune
-- Purpose:
--   Tune thresholds to separate watch vs investigate using baseline logic.
--   Keep param names EXACTLY to avoid the Postgres rename error.
-- =============================================================================

create or replace function public.ms_production_status(
  p_prod_issues_24h integer,
  p_prod_issues_7d integer,
  p_severity_score_7d integer
)
returns text
language sql
stable
as $$
  with x as (
    select
      greatest(coalesce(p_prod_issues_24h, 0), 0) as prod_issues_24h,
      greatest(coalesce(p_prod_issues_7d, 0), 0) as prod_issues_7d,
      greatest(coalesce(p_severity_score_7d, 0), 0) as severity_score_7d
  ),
  b as (
    select
      *,
      greatest(prod_issues_7d / 7.0, 0.25) as baseline_daily,
      case
        when prod_issues_7d = 0 then null
        else prod_issues_24h / greatest(prod_issues_7d / 7.0, 0.25)
      end as trend_ratio
    from x
  )
  select
    case
      when prod_issues_7d = 0 then 'ok'

      -- INCIDENT: require real recency signal (24h activity OR sharp acceleration)
      when severity_score_7d >= 200
       and (
         prod_issues_24h >= 1
         or (trend_ratio is not null and trend_ratio >= 2.0)
       )
        then 'incident'

      -- INVESTIGATE: baseline-aware spike OR clear cluster OR meaningful severity
      when (trend_ratio is not null and trend_ratio >= 1.30)
        or prod_issues_24h >= 2
        or severity_score_7d >= 120
        then 'investigate'

      else 'watch'
    end
  from b;
$$;
