-- ============================================================================
-- File: supabase/migrations/202601102100_production_issue_functions.sql
-- Version: 202601102100
-- Project: Mercy Signal
-- Purpose:
--   Deterministic SQL-only classification and scoring of production issues.
--   This file defines pure functions used by enriched views and decision views.
--
-- Safety notes:
--   - Use CREATE OR REPLACE to avoid breaking dependent views (v_signal_entries_enriched,
--     v_production_decisions, etc.).
--   - IMPORTANT: Parameter names are part of the stored function definition; we keep the
--     existing production name "txt" for _ms_norm to avoid SQLSTATE 42P13.
--   - No data is modified.
--   - No tables or views are dropped.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Normalization helper (lowercase + trim, null-safe)
-- NOTE: keep param name "txt" (matches production)
-- ---------------------------------------------------------------------------

create or replace function public._ms_norm(txt text)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(txt, '')));
$$;

-- ---------------------------------------------------------------------------
-- Keyword-based production issue detection (body text only)
-- ---------------------------------------------------------------------------

create or replace function public._ms_has_prod_keyword(body text)
returns boolean
language sql
immutable
as $$
  select
    public._ms_norm(body) like '%outage%' or
    public._ms_norm(body) like '% down%' or
    public._ms_norm(body) like 'down%' or
    public._ms_norm(body) like '%error%' or
    public._ms_norm(body) like '%incident%' or
    public._ms_norm(body) like '%broken%' or
    public._ms_norm(body) like '%fail%' or
    public._ms_norm(body) like '%failure%' or
    public._ms_norm(body) like '%bug%' or
    public._ms_norm(body) like '%regression%';
$$;

-- ---------------------------------------------------------------------------
-- Binary classifier: is this entry a production issue?
-- ---------------------------------------------------------------------------

create or replace function public.is_production_issue(e public.signal_entries)
returns boolean
language sql
stable
as $$
  select
    (public._ms_norm(e.kind) in ('risk', 'production_issue'))
    or (public._ms_norm(e.severity) in ('high', 'critical'))
    or public._ms_has_prod_keyword(e.body);
$$;

-- ---------------------------------------------------------------------------
-- Base score by kind (pre-multiplier)
-- ---------------------------------------------------------------------------

create or replace function public.production_issue_base_score(e public.signal_entries)
returns integer
language sql
stable
as $$
  select case public._ms_norm(e.kind)
    when 'production_issue' then 40
    when 'risk' then 25
    when 'observation' then 10
    when 'note' then 5
    when 'question' then 5
    else 5
  end;
$$;

-- ---------------------------------------------------------------------------
-- Severity multiplier
-- ---------------------------------------------------------------------------

create or replace function public.production_issue_severity_multiplier(e public.signal_entries)
returns numeric
language sql
stable
as $$
  select case public._ms_norm(e.severity)
    when 'critical' then 2.0
    when 'high' then 1.5
    when 'medium' then 1.0
    when 'low' then 0.5
    else 1.0
  end;
$$;

-- ---------------------------------------------------------------------------
-- Final production issue score (0..100)
-- ---------------------------------------------------------------------------

create or replace function public.production_issue_score(e public.signal_entries)
returns integer
language sql
stable
as $$
  select least(
    100,
    (
      (public.production_issue_base_score(e)::numeric
        * public.production_issue_severity_multiplier(e))
      + (case when public._ms_has_prod_keyword(e.body) then 10 else 0 end)
    )::int
  );
$$;

-- ---------------------------------------------------------------------------
-- Human-readable explanation (for UI + audits)
-- ---------------------------------------------------------------------------

create or replace function public.production_issue_reason(e public.signal_entries)
returns text
language sql
stable
as $$
  select case
    when public._ms_norm(e.kind) = 'production_issue' then
      'kind=production_issue'
    when public._ms_norm(e.kind) = 'risk' then
      'kind=risk'
    when public._ms_norm(e.severity) in ('high', 'critical') then
      'severity=' || public._ms_norm(e.severity)
    when public._ms_has_prod_keyword(e.body) then
      'keyword_match'
    else
      null
  end;
$$;

commit;
