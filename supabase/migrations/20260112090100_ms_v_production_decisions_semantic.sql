-- ============================================================================
-- File: supabase/migrations/20260112090100_ms_v_production_decisions_semantic.sql
-- Version: 20260112-02
-- Project: Mercy Signal
-- Purpose:
--   Replace v_production_decisions to use Mercy Signal semantics.
-- Notes:
--   - Keep minutes_since_last_prod_issue as numeric (matches existing column type).
-- ============================================================================

begin;

create or replace view public.v_production_decisions as
with prod as (
  select
    se.signal_id,

    count(*) filter (
      where public.ms_is_production_issue(se.kind)
        and se.created_at >= now() - interval '24 hours'
    )::int as prod_issues_24h,

    count(*) filter (
      where public.ms_is_production_issue(se.kind)
        and se.created_at >= now() - interval '7 days'
    )::int as prod_issues_7d,

    max(se.created_at) filter (
      where public.ms_is_production_issue(se.kind)
    ) as last_prod_issue_at

  from public.signal_entries se
  group by se.signal_id
),
enriched as (
  select
    p.signal_id,
    coalesce(p.prod_issues_24h, 0) as prod_issues_24h,
    coalesce(p.prod_issues_7d, 0) as prod_issues_7d,
    p.last_prod_issue_at,

    case
      when p.last_prod_issue_at is null then null::numeric
      else greatest(
        floor(extract(epoch from (now() - p.last_prod_issue_at)) / 60),
        0
      )::numeric
    end as minutes_since_last_prod_issue,

    public.ms_severity_score_7d(p.signal_id) as severity_score_7d
  from prod p
)
select
  e.signal_id,
  e.prod_issues_24h,
  e.prod_issues_7d,
  e.last_prod_issue_at,
  e.minutes_since_last_prod_issue,
  e.severity_score_7d,
  public.ms_production_status(e.prod_issues_24h, e.prod_issues_7d) as production_status
from enriched e;

comment on view public.v_production_decisions
is 'Mercy Signal semantic production decision view (counts, recency, score, status).';

commit;
