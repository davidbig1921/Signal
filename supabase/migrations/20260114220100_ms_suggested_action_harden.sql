-- =============================================================================
-- Mercy Signal
-- Migration: ms_suggested_action_harden
-- Purpose:
--   - Enforce the 4-code contract: monitor / investigate / page_oncall / noop
--   - Prevent enum/domain mismatch errors (22P02)
--   - Normalize any legacy/extra codes to a safe canonical code
-- =============================================================================

begin;

-- 1) Canonical normalizer (always returns one of the 4 codes)
create or replace function public.ms_suggested_action_code_normalize(p_code text)
returns text
language sql
immutable
as $$
  select
    case upper(coalesce(p_code, ''))
      when 'MONITOR' then 'monitor'
      when 'INVESTIGATE' then 'investigate'
      when 'PAGE_ONCALL' then 'page_oncall'
      when 'NOOP' then 'noop'

      -- collapse any legacy / “creative” codes safely:
      when 'MONITOR_SERVICE_HEALTH' then 'monitor'
      when 'MONITOR_HEALTH' then 'monitor'
      when 'CHECK_SERVICE_HEALTH' then 'monitor'
      when 'MONITORING' then 'monitor'
      else 'monitor'
    end
$$;

-- 2) Make ms_suggested_action_text() defensively normalize input
--    (keeps your locked wording but prevents bad inputs from crashing)
create or replace function public.ms_suggested_action_text(p_code text)
returns text
language sql
stable
as $$
  select
    case public.ms_suggested_action_code_normalize(p_code)
      when 'page_oncall' then 'Page on-call and mitigate the incident now.'
      when 'investigate' then 'Investigate recent changes and confirm impact.'
      when 'monitor' then 'Monitor closely and watch for trend changes.'
      else 'No action needed.'
    end
$$;

commit;
