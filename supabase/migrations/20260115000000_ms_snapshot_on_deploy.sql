-- =============================================================================
-- Mercy Signal
-- Migration: ms_snapshot_on_deploy
-- Purpose:
--   - Bulletproof deploy snapshots of decision outputs (v_production_decisions_explain)
--   - Harden suggested_action_text so unknown codes never crash queries
--   - Provide a stable audit trail you can diff between deploys
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 0) HARDEN: safe overload for suggested action text
--    Why:
--      - Your DB currently has an enum/domain for suggested_action_code.
--      - Some older/stray callers may pass unexpected strings (e.g. MONITOR_SERVICE_HEALTH).
--      - That must NEVER crash the decisions views. Unknown => noop.
--
--    This keeps your "locked wording" source-of-truth function as-is.
--    We just add a text overload that normalizes safely.
-- -----------------------------------------------------------------------------

create or replace function public.ms_suggested_action_text(p_code text)
returns text
language plpgsql
stable
as $$
declare
  normalized text;
  has_domain boolean;
  has_enum boolean;
  out_text text;
begin
  normalized := lower(trim(coalesce(p_code, '')));

  if normalized not in ('monitor', 'investigate', 'page_oncall', 'noop') then
    normalized := 'noop';
  end if;

  -- Detect which type exists (domain first, then enum). Avoid hard failures.
  has_domain := to_regtype('public.ms_suggested_action_code_domain') is not null;
  has_enum   := to_regtype('public.ms_suggested_action_code') is not null;

  if has_domain then
    execute
      'select public.ms_suggested_action_text(($1)::public.ms_suggested_action_code_domain)'
      into out_text
      using normalized;
    return out_text;
  elsif has_enum then
    execute
      'select public.ms_suggested_action_text(($1)::public.ms_suggested_action_code)'
      into out_text
      using normalized;
    return out_text;
  else
    -- Absolute fallback: never crash.
    -- If your locked function/types are missing for some reason, return a safe noop string.
    return 'No action.';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 1) SNAPSHOT TABLES
-- -----------------------------------------------------------------------------

create table if not exists public.ms_deploy_snapshot (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  reason text null,
  git_sha text null,
  notes text null
);

create table if not exists public.ms_deploy_snapshot_production_decisions (
  snapshot_id bigint not null references public.ms_deploy_snapshot(id) on delete cascade,
  signal_id uuid not null,

  prod_issues_24h integer not null,
  prod_issues_7d integer not null,
  last_prod_issue_at timestamptz null,
  minutes_since_last_prod_issue numeric null,
  severity_score_7d integer not null,

  production_status text not null,
  suggested_action_code text not null,
  suggested_action_text text not null,

  -- explain fields (keep as text to avoid domain/enum return-type migration pain)
  trend_24h_vs_7d text null,
  confidence text null,
  severity_label text null,
  status_reason_code text null,

  primary key (snapshot_id, signal_id)
);

-- -----------------------------------------------------------------------------
-- 2) SNAPSHOT FUNCTION
--    - Inserts one snapshot header + all rows from v_production_decisions_explain
--    - Uses explicit columns (no c.*)
--    - Uses the safe ms_suggested_action_text(text) overload automatically
-- -----------------------------------------------------------------------------

create or replace function public.ms_take_deploy_snapshot(
  p_reason text default 'deploy',
  p_git_sha text default null,
  p_notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  sid bigint;
  view_exists boolean;
begin
  view_exists := to_regclass('public.v_production_decisions_explain') is not null;
  if not view_exists then
    raise exception 'v_production_decisions_explain does not exist; cannot snapshot';
  end if;

  insert into public.ms_deploy_snapshot(reason, git_sha, notes)
  values (p_reason, p_git_sha, p_notes)
  returning id into sid;

  insert into public.ms_deploy_snapshot_production_decisions (
    snapshot_id,
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    production_status,
    suggested_action_code,
    suggested_action_text,
    trend_24h_vs_7d,
    confidence,
    severity_label,
    status_reason_code
  )
  select
    sid,
    e.signal_id,
    e.prod_issues_24h,
    e.prod_issues_7d,
    e.last_prod_issue_at,
    e.minutes_since_last_prod_issue,
    e.severity_score_7d,
    e.production_status::text,
    e.suggested_action_code::text,
    public.ms_suggested_action_text(e.suggested_action_code::text),
    e.trend_24h_vs_7d::text,
    e.confidence::text,
    e.severity_label::text,
    e.status_reason_code::text
  from public.v_production_decisions_explain e;

  return sid;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3) "AUTOMATIC" SNAPSHOT ON DEPLOY
--    This migration runs once per environment, so it creates one snapshot entry.
--    Future deploys should include another migration that calls ms_take_deploy_snapshot().
-- -----------------------------------------------------------------------------
select public.ms_take_deploy_snapshot('deploy', null, 'auto snapshot from migration');

commit;
