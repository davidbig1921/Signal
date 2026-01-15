-- ============================================================================
-- Migration: ms_v_production_decisions_add_suggested_action
-- Purpose:
--   - Extend public.v_production_decisions with deterministic suggested action
--   - Keep existing logic intact (wrap existing view SQL as base)
-- Notes:
--   - Uses existing function: public.ms_suggested_action_text(text)
--   - Adds columns at the end to avoid breaking consumers
-- ============================================================================

begin;

create or replace view public.v_production_decisions as
with base as (
  -- ===== EXISTING VIEW SQL (unchanged) ======================================
  WITH prod AS (
    SELECT
      e.signal_id,
      e.created_at,
      e.is_production_issue,
      e.production_issue_score,
      CASE
        WHEN e.created_at >= (now() - '24:00:00'::interval) THEN 1.0
        WHEN e.created_at >= (now() - '3 days'::interval) THEN 0.7
        WHEN e.created_at >= (now() - '7 days'::interval) THEN 0.4
        ELSE 0.1
      END AS recency_weight
    FROM v_signal_entries_enriched e
  ),
  agg AS (
    SELECT
      p.signal_id,
      count(*) FILTER (
        WHERE p.is_production_issue
          AND p.created_at >= (now() - '24:00:00'::interval)
      )::integer AS prod_issues_24h,
      count(*) FILTER (
        WHERE p.is_production_issue
          AND p.created_at >= (now() - '7 days'::interval)
      )::integer AS prod_issues_7d,
      max(p.created_at) FILTER (WHERE p.is_production_issue) AS last_prod_issue_at,
      COALESCE(
        sum(p.production_issue_score::numeric * p.recency_weight)
          FILTER (
            WHERE p.is_production_issue
              AND p.created_at >= (now() - '7 days'::interval)
          ),
        0::numeric
      )::integer AS severity_score_7d
    FROM prod p
    GROUP BY p.signal_id
  ),
  inner_base AS (
    SELECT
      a.signal_id,
      a.prod_issues_24h,
      a.prod_issues_7d,
      a.last_prod_issue_at,
      CASE
        WHEN a.last_prod_issue_at IS NULL THEN NULL::numeric
        ELSE EXTRACT(epoch FROM now() - a.last_prod_issue_at) / 60.0
      END AS minutes_since_last_prod_issue,
      a.severity_score_7d
    FROM agg a
  )
  SELECT
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    ms_production_status(
      prod_issues_24h,
      prod_issues_7d,
      minutes_since_last_prod_issue,
      severity_score_7d
    ) AS production_status
  FROM inner_base b
  -- ==========================================================================
)
select
  base.signal_id,
  base.prod_issues_24h,
  base.prod_issues_7d,
  base.last_prod_issue_at,
  base.minutes_since_last_prod_issue,
  base.severity_score_7d,
  base.production_status,

  -- Deterministic action code derived ONLY from production_status
  case base.production_status
    when 'incident'     then 'page_oncall'
    when 'investigate'  then 'investigate'
    when 'watch'        then 'monitor'
    else 'noop'
  end as suggested_action_code,

  -- Deterministic wording from contract function
  public.ms_suggested_action_text(
    case base.production_status
      when 'incident'     then 'page_oncall'
      when 'investigate'  then 'investigate'
      when 'watch'        then 'monitor'
      else 'noop'
    end
  ) as suggested_action_text
from base;

commit;
