-- ============================================================================
-- File: supabase/migrations/20260112090000_ms_decision_semantics.sql
-- Version: 20260112-03
-- Project: Mercy Signal
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 0) Drop dependent objects in safe order
--    Views MUST be dropped before functions they depend on
-- ----------------------------------------------------------------------------
drop view if exists public.v_production_decisions;

drop function if exists public.ms_production_status(integer, integer);
drop function if exists public.ms_severity_score_7d(uuid);
drop function if exists public.ms_is_production_issue(text);

-- ----------------------------------------------------------------------------
-- 1) What counts as a production issue (deterministic rule)
-- ----------------------------------------------------------------------------
create function public.ms_is_production_issue(entry_kind text)
returns boolean
language sql
stable
as $$
  select
    case
      when entry_kind is null then false
      when entry_kind in (
        'prod_incident',
        'prod_error',
        'prod_outage',
        'prod_degradation',
        'prod_regression',
        'prod_alert'
      ) then true
      when entry_kind like 'prod_%' then true
      else false
    end;
$$;

comment on function public.ms_is_production_issue(text)
is 'True if entry_kind is considered a production issue (deterministic rule).';

-- ----------------------------------------------------------------------------
-- 2) Severity score (7 days) — KEEP AS INTEGER
-- ----------------------------------------------------------------------------
create function public.ms_severity_score_7d(p_signal_id uuid)
returns integer
language sql
stable
as $$
  select
    coalesce(count(*)::integer, 0)
  from public.signal_entries se
  where se.signal_id = p_signal_id
    and public.ms_is_production_issue(se.kind)
    and se.created_at >= now() - interval '7 days';
$$;

comment on function public.ms_severity_score_7d(uuid)
is 'Baseline severity score = count of production issues in last 7 days (integer).';

-- ----------------------------------------------------------------------------
-- 3) Production status classification
-- ----------------------------------------------------------------------------
create function public.ms_production_status(
  p_prod_issues_24h integer,
  p_prod_issues_7d integer
)
returns text
language sql
stable
as $$
  select
    case
      when coalesce(p_prod_issues_24h, 0) >= 3 then 'incident'
      when coalesce(p_prod_issues_24h, 0) >= 1 then 'investigate'
      when coalesce(p_prod_issues_7d, 0) >= 2 then 'watch'
      else 'ok'
    end;
$$;

comment on function public.ms_production_status(integer, integer)
is 'Classifies production status from 24h/7d counts using deterministic thresholds.';

commit;
