-- ============================================================================
-- Migration: ms_suggested_action_text_lock
-- Purpose:
--   - Deterministic mapping: code -> fixed copy
--   - Exhaustive by using enum input
--   - Ensure views output enum-typed suggested_action_code
-- ============================================================================

begin;

-- 1) Replace function with enum input (forces exhaustiveness)
create or replace function public.ms_suggested_action_text(
  p_code public.ms_suggested_action_code
)
returns text
language sql
stable
as $$
  select case p_code
    when 'noop'        then 'No action needed.'
    when 'monitor'     then 'Monitor signals and wait for more evidence.'
    when 'investigate' then 'Investigate the suspected production issue.'
    when 'mitigate'    then 'Mitigate impact and reduce risk.'
    when 'rollback'    then 'Rollback the most likely recent change.'
    when 'page_oncall' then 'Page on-call now.'
  end;
$$;

-- 2) OPTIONAL: if you still need a compatibility wrapper (e.g., views currently pass text)
-- Keeps older callers working while you migrate views.
create or replace function public.ms_suggested_action_text(p_code text)
returns text
language sql
stable
as $$
  select public.ms_suggested_action_text(p_code::public.ms_suggested_action_code);
$$;

-- 3) Update your view(s) to cast suggested_action_code to enum
-- Example for v_production_decisions (adjust to your actual view definition):
-- create or replace view public.v_production_decisions as
-- select
--   ...,
--   (suggested_action_code::public.ms_suggested_action_code) as suggested_action_code,
--   public.ms_suggested_action_text(suggested_action_code::public.ms_suggested_action_code) as suggested_action_text,
--   ...
-- from ...;

commit;
