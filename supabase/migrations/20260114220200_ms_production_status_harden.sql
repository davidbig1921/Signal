-- =============================================================================
-- Mercy Signal
-- Migration: ms_production_status_harden
-- Purpose:
--   - Stop overload chaos + param-name rename failures (42P13)
--   - Keep canonical signature stable and return type stable (text)
--   - Drop only legacy overloads if truly unused
-- =============================================================================

begin;

-- Drop legacy 3-arg overload ONLY IF unused
do $$
declare dep_count int;
begin
  select count(*)
    into dep_count
  from pg_depend d
  join pg_proc p on p.oid = d.refobjid
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.oid::regprocedure::text = 'public.ms_production_status(integer,integer,integer)';

  if dep_count = 0 then
    execute 'drop function if exists public.ms_production_status(integer,integer,integer);';
  end if;
end $$;

-- Canonical: KEEP return type text. KEEP parameter NAMES EXACTLY AS INSTALLED.
-- If your installed canonical uses prod_issues_24h/prod_issues_7d/... then keep these.
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
         or (minutes_since_last_prod_issue is not null and minutes_since_last_prod_issue <= 360)
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

commit;
