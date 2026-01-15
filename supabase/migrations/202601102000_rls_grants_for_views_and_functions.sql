-- =============================================================================
-- Migration: rls_grants_for_views_and_functions
-- Purpose:
--   Grant read/execute permissions WITHOUT assuming views already exist.
--   This avoids ordering-related migration failures.
-- =============================================================================

do $$
begin
  -- Base decisions view
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'v_production_decisions'
  ) then
    grant select on public.v_production_decisions to authenticated;
  end if;

  -- Explain view (may be created later)
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'v_production_decisions_explain'
  ) then
    grant select on public.v_production_decisions_explain to authenticated;
  end if;
end
$$;

-- Functions (safe to grant even if unused)
grant execute on function public.is_production_issue(text, text) to authenticated;
grant execute on function public.classify_production_issue(text, text) to authenticated;
