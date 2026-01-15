-- =============================================================================
-- Mercy Signal
-- Migration: ms_production_status_tune_watch_investigate
-- Purpose:
--   - Canonical production_status classifier with baseline (7d/7) trend logic
--   - Separate WATCH vs INVESTIGATE consistently
--   - Keep canonical function signature stable (do NOT drop it)
--   - Rebuild views safely (drop+create views, no cascade)
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 0) Drop dependent views FIRST (no cascade) so later drops succeed
-- -----------------------------------------------------------------------------
drop view if exists public.v_production_decisions_explain;
drop view if exists public.v_production_decisions;

-- -----------------------------------------------------------------------------
-- 1) Canonical classifier
--    IMPORTANT: Do NOT drop ms_production_status(integer,integer,numeric,integer)
--    because views depend on it. Use CREATE OR REPLACE only.
-- -----------------------------------------------------------------------------

-- Drop only truly-unused/older signatures IF they exist and are safe to drop.
drop function if exists public.ms_production_status(integer, integer, integer);
drop function if exists public.ms_production_status(integer, integer, numeric);

-- FIX: parameter NAMES must match the already-existing function, or Postgres errors (42P13)
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
-- 1b) Compatibility overload (only if you still have older migrations calling it)
-- Signature: (integer, integer, integer, numeric)
--
-- IMPORTANT:
--   Postgres can throw 42P13 if you CREATE OR REPLACE and the *parameter names*
--   differ from what already exists for that exact signature.
--   So: create it ONLY IF missing; otherwise leave it untouched.
-- -----------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.ms_production_status(integer,integer,integer,numeric)') is null then
    execute $fn$
      create function public.ms_production_status(
        prod_issues_24h integer,
        prod_issues_7d integer,
        minutes_since_last_prod_issue integer,
        severity_score_7d numeric
      )
      returns text
      language sql
      stable
      as $body$
        select public.ms_production_status(
          prod_issues_24h,
          prod_issues_7d,
          minutes_since_last_prod_issue::numeric,
          severity_score_7d::integer
        );
      $body$;
    $fn$;
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 2) Rebuild v_production_decisions
--    Must include suggested_action_code/text columns (append-only contract).
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
)
select
  s.signal_id,
  s.prod_issues_24h,
  s.prod_issues_7d,
  s.last_prod_issue_at,
  s.minutes_since_last_prod_issue,
  s.severity_score_7d,
  s.production_status,

  case s.production_status
    when 'incident'     then 'page_oncall'
    when 'investigate'  then 'investigate'
    when 'watch'        then 'monitor'
    else 'noop'
  end as suggested_action_code,

  public.ms_suggested_action_text(
    case s.production_status
      when 'incident'     then 'page_oncall'
      when 'investigate'  then 'investigate'
      when 'watch'        then 'monitor'
      else 'noop'
    end
  ) as suggested_action_text

from scored s;

-- -----------------------------------------------------------------------------
-- 3) Rebuild explain view aligned to the SAME baseline logic
--    No prose fields; emit status_reason_code + trend/confidence/severity.
-- -----------------------------------------------------------------------------
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

    greatest(d.prod_issues_7d / 7.0, 0.25) as baseline_daily,

    case
      when d.prod_issues_7d = 0 then null
      else d.prod_issues_24h / greatest(d.prod_issues_7d / 7.0, 0.25)
    end as trend_ratio,

    case
      when d.prod_issues_7d = 0 and d.prod_issues_24h = 0 then 'stable'
      when (d.prod_issues_7d > 0) and (d.prod_issues_24h / greatest(d.prod_issues_7d / 7.0, 0.25) >= 1.5) then 'worsening'
      when (d.prod_issues_7d > 0) and (d.prod_issues_24h / greatest(d.prod_issues_7d / 7.0, 0.25) <= 0.67) then 'improving'
      else 'stable'
    end as trend_24h_vs_7d,

    least(
      100,
      (d.prod_issues_7d * 6)
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
  c.*,

  case
    when c.confidence_score >= 70 then 'high'
    when c.confidence_score >= 35 then 'medium'
    else 'low'
  end as confidence,

  case
    when c.severity_score_7d >= 200 then 'High'
    when c.severity_score_7d >= 80 then 'Medium'
    when c.severity_score_7d > 0 then 'Low'
    else 'None'
  end as severity_label,

  case
    when c.production_status = 'incident' then 'INCIDENT_RECENT_HIGH_SEVERITY'
    when c.production_status = 'investigate'
      and c.trend_ratio is not null and c.trend_ratio >= 1.5 and c.prod_issues_24h >= 1
      then 'INVESTIGATE_WORSENING_VS_BASELINE'
    when c.production_status = 'investigate' and c.prod_issues_24h >= 2
      then 'INVESTIGATE_CLUSTER_24H'
    when c.production_status = 'investigate' and c.severity_score_7d >= 120
      then 'INVESTIGATE_SUSTAINED_SEVERITY_7D'
    when c.production_status = 'watch' then 'WATCH_RECENT_NOT_SPIKING'
    else 'OK_NO_RECENT_PROD_ISSUES'
  end as status_reason_code

from calc c;

grant select on public.v_production_decisions to authenticated;
grant select on public.v_production_decisions_explain to authenticated;

commit;
