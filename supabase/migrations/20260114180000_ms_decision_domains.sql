-- =============================================================================
-- Mercy Signal
-- Migration: ms_decision_domains
-- Purpose:
--   - Centralize and validate decision "codes" and labels
--   - Provide reusable CHECK-like helpers for views/tables
-- Notes:
--   - We use DOMAIN for strong validation where possible.
--   - Views can't have CHECK constraints, but domains still enforce at projection time.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Domains (strongest primitive we can use without creating tables)
-- -----------------------------------------------------------------------------

do $$ begin
  if not exists (select 1 from pg_type where typname = 'ms_production_status_domain') then
    create domain public.ms_production_status_domain as text
      check (value in ('ok','watch','investigate','incident'));
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'ms_trend_label_domain') then
    create domain public.ms_trend_label_domain as text
      check (value in ('worsening','stable','improving'));
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'ms_confidence_label_domain') then
    create domain public.ms_confidence_label_domain as text
      check (value in ('high','medium','low'));
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'ms_severity_label_domain') then
    create domain public.ms_severity_label_domain as text
      check (value in ('High','Medium','Low','None'));
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'ms_suggested_action_code_domain') then
    create domain public.ms_suggested_action_code_domain as text
      check (value in ('page_oncall','investigate','monitor','noop'));
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'ms_status_reason_code_domain') then
    create domain public.ms_status_reason_code_domain as text
      check (value in (
        'INCIDENT_RECENT_HIGH_SEVERITY',
        'INVESTIGATE_WORSENING_VS_BASELINE',
        'INVESTIGATE_CLUSTER_24H',
        'INVESTIGATE_SUSTAINED_SEVERITY_7D',
        'WATCH_RECENT_NOT_SPIKING',
        'OK_NO_RECENT_PROD_ISSUES'
      ));
  end if;
end $$;

commit;
