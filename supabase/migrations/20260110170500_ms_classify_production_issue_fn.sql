-- =============================================================================
-- Migration: ms_classify_production_issue_fn
-- Purpose:
--   Provide public.classify_production_issue(p_kind, p_body) BEFORE remote_schema,
--   using the SAME parameter names to avoid 42P13.
-- =============================================================================

create or replace function public.classify_production_issue(p_kind text, p_body text)
returns boolean
language sql
immutable
strict
as $$
  select public.is_production_issue(p_kind, p_body);
$$;
