-- =============================================================================
-- Migration: ms_v_production_decisions_tune_recency
-- Purpose: prevent stale 7d severity from triggering INCIDENT when 24h is quiet
-- =============================================================================

create or replace view v_production_decisions as
with base as (
  select
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d
  from v_production_decisions  -- <-- IMPORTANT: replace this line with your real base source
)
select
  b.*,

  case
    when b.prod_issues_7d = 0 then 'ok'

    -- INCIDENT: high severity + recent activity
    when b.severity_score_7d >= 200
     and (
       b.prod_issues_24h >= 1
       or (b.minutes_since_last_prod_issue is not null and b.minutes_since_last_prod_issue <= 360) -- 6h
     )
      then 'incident'

    -- INVESTIGATE: high-ish severity OR recent cluster
    when b.severity_score_7d >= 120
     or b.prod_issues_24h >= 2
      then 'investigate'

    -- WATCH: something happened in 7d but not actively spiking
    else 'watch'
  end as production_status
from base b;
