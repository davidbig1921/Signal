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
-- 0) HARDEN: safe, normalization-only wrapper
--    This DOES NOT cast into enum/domain (so it cannot throw 22P02).
--    It returns locked text for the known 4 codes, otherwise falls back to noop.
-- -----------------------------------------------------------------------------
create or replace function public.ms_suggested_action_text_safe(p_code text)
returns text
language sql
stable
as $$
  select public.ms_suggested_action_text(
    case lower(trim(coalesce(p_code, '')))
      when 'monitor' then 'monitor'
      when 'investigate' then 'investigate'
      when 'page_oncall' then 'page_oncall'
      when 'noop' then 'noop'
      else 'noop'
    end
  );
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

  trend_24h_vs_7d text null,
  confidence text null,
  severity_label text null,
  status_reason_code text null,

  primary key (snapshot_id, signal_id)
);

-- -----------------------------------------------------------------------------
-- 2) SNAPSHOT FUNCTION
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
begin
  if to_regclass('public.v_production_decisions_explain') is null then
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
    public.ms_suggested_action_text_safe(e.suggested_action_code::text),
    e.trend_24h_vs_7d::text,
    e.confidence::text,
    e.severity_label::text,
    e.status_reason_code::text
  from public.v_production_decisions_explain e;

  return sid;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3) OPTIONAL: take one snapshot now (once, when this migration is first applied)
-- -----------------------------------------------------------------------------
select public.ms_take_deploy_snapshot('deploy', null, 'auto snapshot from migration');

commit;
