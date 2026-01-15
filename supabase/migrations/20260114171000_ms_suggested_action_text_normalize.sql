-- ============================================================================
-- Migration: ms_suggested_action_text_normalize
-- Purpose:
--   - Preserve existing (legacy) suggested_action wording function
--   - Add deterministic normalization so new codes (page_oncall, investigate, etc.)
--     map to the legacy code set used by existing wording.
-- Notes:
--   - This avoids changing legacy text and prevents code/text mismatch.
--   - Only maps the 4 codes currently emitted by v_production_decisions:
--       page_oncall, investigate, monitor, noop
-- ============================================================================

begin;

-- 1) Rename the existing function to *_legacy (only once)
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'ms_suggested_action_text'
      and pg_get_function_identity_arguments(p.oid) = 'p_code text'
  )
  and not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'ms_suggested_action_text_legacy'
      and pg_get_function_identity_arguments(p.oid) = 'p_code text'
  )
  then
    alter function public.ms_suggested_action_text(text)
      rename to ms_suggested_action_text_legacy;
  end if;
end $$;

-- 2) Create the new wrapper with normalization
create or replace function public.ms_suggested_action_text(p_code text)
returns text
language sql
stable
as $$
  select public.ms_suggested_action_text_legacy(
    case
      -- New codes (lowercase) -> Legacy codes (uppercase)
      when lower(p_code) = 'page_oncall' then 'INCIDENT_ESCALATE_NOW'
      when lower(p_code) = 'investigate' then 'INVESTIGATE_TODAY'
      when lower(p_code) = 'monitor' then 'MONITOR_SERVICE_HEALTH'
      when lower(p_code) = 'noop' then 'NO_ACTION'

      -- Pass through anything else to legacy (keeps backward compatibility)
      else p_code
    end
  );
$$;

commit;
