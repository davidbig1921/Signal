-- ============================================================================
-- File: supabase/migrations/20260112140000_ms_v_production_decisions_explain.sql
-- Project: Mercy Signal
-- Purpose:
--   Add explainability columns to v_production_decisions:
--     - status_reason (why this status)
--     - action_hint  (what to do next)
-- Notes:
--   - Keeps existing column types stable:
--       severity_score_7d: integer
--       minutes_since_last_prod_issue: numeric
-- ============================================================================

begin;

create or replace view public.v_production_decisions as
with prod_counts as (
  select
    s.id as signal_id,

    coalesce(
      sum(
        case
          when public.ms_is_production_issue(se.kind)
           and se.created_at >= now() - interval '24 hours'
          then 1 else 0
        end
      )::integer,
      0
    ) as prod_issues_24h,

    coalesce(
      sum(
        case
          when public.ms_is_production_issue(se.kind)
           and se.created_at >= now() - interval '7 days'
          then 1 else 0
        end
      )::integer,
      0
    ) as prod_issues_7d,

    max(
      case
        when public.ms_is_production_issue(se.kind) then se.created_at
        else null
      end
    ) as last_prod_issue_at

  from public.signals s
  left join public.signal_entries se
    on se.signal_id = s.id
  group by s.id
),
enriched as (
  select
    pc.signal_id,
    pc.prod_issues_24h,
    pc.prod_issues_7d,
    pc.last_prod_issue_at,

    case
      when pc.last_prod_issue_at is null then null::numeric
      else greatest(
        0,
        floor(extract(epoch from (now() - pc.last_prod_issue_at)) / 60)
      )::numeric
    end as minutes_since_last_prod_issue,

    public.ms_severity_score_7d(pc.signal_id) as severity_score_7d,

    public.ms_production_status(pc.prod_issues_24h, pc.prod_issues_7d) as production_status

  from prod_counts pc
)
select
  e.signal_id,
  e.prod_issues_24h,
  e.prod_issues_7d,
  e.last_prod_issue_at,
  e.minutes_since_last_prod_issue,
  e.severity_score_7d,
  e.production_status,

  case
    when coalesce(e.prod_issues_24h, 0) >= 3 then '24h production issues >= 3'
    when coalesce(e.prod_issues_24h, 0) >= 1 then '24h production issues >= 1'
    when coalesce(e.prod_issues_7d, 0) >= 2 then '7d production issues >= 2'
    else 'No production thresholds triggered'
  end as status_reason,

  case e.production_status
    when 'incident' then 'Open an incident. Review most recent production entries and mitigate.'
    when 'investigate' then 'Investigate last 24h production entries. Confirm impact and scope.'
    when 'watch' then 'Monitor. Look for recurring patterns over the last 7 days.'
    else 'No action needed.'
  end as action_hint

from enriched e;

comment on view public.v_production_decisions is
  'Production Decisions with deterministic explainability (status_reason, action_hint).';

commit;
