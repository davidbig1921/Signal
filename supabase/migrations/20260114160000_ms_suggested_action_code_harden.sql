-- ============================================================================
-- Migration: ms_suggested_action_code_harden
-- Purpose:
--   - Lock suggested_action_code to a finite set (enum)
--   - Ensure views/tables can’t emit unknown codes
-- ============================================================================

begin;

-- 1) Enum type (idempotent-ish)
do $$
begin
  if not exists (select 1 from pg_type where typname = 'ms_suggested_action_code') then
    create type public.ms_suggested_action_code as enum (
      -- Keep this list EXACTLY aligned with ms_suggested_action_text()
      'noop',
      'monitor',
      'investigate',
      'mitigate',
      'rollback',
      'page_oncall'
    );
  end if;
end $$;

-- 2) If you store suggested_action_code in a table, harden it here.
-- If it’s only in views, skip this block.
-- Example (adjust table/column names if you have them):
-- alter table public.signals
--   alter column suggested_action_code type public.ms_suggested_action_code
--   using suggested_action_code::public.ms_suggested_action_code;

-- 3) Ensure the text function is exhaustive and stable (next migration handles function body if needed)

commit;
