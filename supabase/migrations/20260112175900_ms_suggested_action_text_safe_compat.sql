-- =============================================================================
-- Migration: ms_suggested_action_text_safe_compat
-- Purpose:
--   - Provide ms_suggested_action_text_safe(text) early in history so views compile
--   - If the real implementation exists later, it can safely replace this stub
-- =============================================================================

begin;

create or replace function public.ms_suggested_action_text_safe(p_code text)
returns text
language sql
stable
as $$
  select case coalesce(p_code, '')
    when 'page_oncall'   then 'Page on-call.'
    when 'investigate'   then 'Investigate.'
    when 'monitor'       then 'Monitor.'
    when 'noop'          then 'No action.'
    else 'No action.'
  end;
$$;

commit;
