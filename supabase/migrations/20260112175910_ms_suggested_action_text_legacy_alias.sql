-- =============================================================================
-- Migration: ms_suggested_action_text_legacy_alias
-- Purpose:
--   - Provide legacy ms_suggested_action_text(text) so older migrations compile
--   - Delegate to ms_suggested_action_text_safe(text)
-- =============================================================================

begin;

create or replace function public.ms_suggested_action_text(p_code text)
returns text
language sql
stable
as $$
  select public.ms_suggested_action_text_safe(p_code);
$$;

commit;
