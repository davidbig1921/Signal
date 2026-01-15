-- =============================================================================
-- Mercy Signal
-- Migration: ms_production_status_overloads_lock
-- Purpose:
--   - Permanently stop 42P13 overload rename loops
--   - Re-create BOTH overloads keeping EXACT existing parameter names + return type
--   - Optionally drop legacy 3-arg overload (only if it exists)
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 0) Optional cleanup: drop legacy 3-arg overload if it exists.
--    (Your DB says it does NOT exist right now, but this is safe.)
-- -----------------------------------------------------------------------------
drop function if exists public.ms_production_status(integer,integer,integer);

-- -----------------------------------------------------------------------------
-- 1) Canonical: (integer, integer, numeric, integer) -> text
--    MUST keep these exact arg names:
--      prod_issues_24h, prod_issues_7d, minutes_since_last_prod_issue, severity_score_7d
-- -----------------------------------------------------------------------------
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
  with m as (
    select
      greatest(prod_issues_7d, 0) as prod_issues_7d,
      greatest(prod_issues_24h, 0) as prod_issues_24h,
      minutes_since_last_prod_issue as minutes_since_last_prod_issue,
      greatest(severity_score_7d, 0) as severity_score_7d,
      greatest(greatest(prod_issues_7d, 0) / 7.0, 0.25) as baseline_daily,
      case
        when greatest(prod_issues_7d, 0) = 0 then null
        else greatest(prod_issues_24h, 0)
          / greatest(greatest(prod_issues_7d, 0) / 7.0, 0.25)
      end as trend_ratio
  )
  select
    case
      when prod_issues_7d = 0 then 'ok'

      when severity_score_7d >= 200
       and (
         prod_issues_24h >= 1
         or (minutes_since_last_prod_issue is not null and minutes_since_last_prod_issue <= 360) -- 6h
         or (trend_ratio is not null and trend_ratio >= 2.0)
       )
        then 'incident'

      when
        ((trend_ratio is not null and trend_ratio >= 1.5) and prod_issues_24h >= 1)
        or prod_issues_24h >= 2
        or severity_score_7d >= 120
        then 'investigate'

      else 'watch'
    end
  from m;
$$;

-- -----------------------------------------------------------------------------
-- 2) Compatibility overload: (integer, integer, integer, numeric) -> text
--    MUST keep these exact arg names:
--      p_prod_issues_24h, p_prod_issues_7d, p_minutes_since_last_prod_issue, p_severity_score_7d
-- -----------------------------------------------------------------------------
create or replace function public.ms_production_status(
  p_prod_issues_24h integer,
  p_prod_issues_7d integer,
  p_minutes_since_last_prod_issue integer,
  p_severity_score_7d numeric
)
returns text
language sql
stable
as $$
  select public.ms_production_status(
    p_prod_issues_24h,
    p_prod_issues_7d,
    p_minutes_since_last_prod_issue::numeric,
    p_severity_score_7d::integer
  );
$$;

commit;
