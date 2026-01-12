-- =============================================================================
-- Migration: ms_production_status_recency_gate
-- Purpose:
--   Tune production status classification so "incident" requires recency.
--   Signature remains the same to avoid breaking v_production_decisions.
-- =============================================================================

create or replace function public.ms_production_status(
  prod_issues_24h integer,
  prod_issues_7d integer,
  severity_score_7d integer
)
returns text
language sql
stable
as $$
  select
    case
      -- No production issues in 7d => OK
      when coalesce(prod_issues_7d, 0) = 0 then 'ok'

      -- INCIDENT requires recency (fresh signal)
      when coalesce(prod_issues_24h, 0) >= 1
       and coalesce(severity_score_7d, 0) >= 200
        then 'incident'

      -- INVESTIGATE: meaningful risk even if not actively spiking
      when coalesce(severity_score_7d, 0) >= 120
        or coalesce(prod_issues_24h, 0) >= 2
        then 'investigate'

      -- WATCH: something happened in 7d but not high confidence / not spiking
      else 'watch'
    end;
$$;

comment on function public.ms_production_status(integer, integer, integer) is
'Mercy Signal production status: incident requires prod_issues_24h>=1 + severity>=200; investigate if severity>=120 or prod_issues_24h>=2; watch otherwise; ok when prod_issues_7d=0.';
