-- ============================================================================
-- Migration: ms_production_status_compat
-- Purpose:
--   - Provide backward/alternate signature expected by older view migrations:
--       ms_production_status(integer, integer, integer, numeric)
--   - Delegate to the canonical signature used elsewhere.
-- ============================================================================

begin;

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
