-- ============================================================================
-- Mercy Signal
-- Migration: ms_v_production_decisions_explain_fix
-- Purpose:
--   Add deterministic explainability fields (status_reason, action_hint)
--   without changing the trusted v_production_decisions status/severity logic.
--
-- Strategy:
--   Create a wrapper view v_production_decisions_explain that SELECTs from
--   v_production_decisions and adds computed text columns.
-- ============================================================================

create or replace view public.v_production_decisions_explain as
select
  d.*,

  -- ----------------------------
  -- status_reason (deterministic)
  -- ----------------------------
  case
    when d.production_status = 'incident' then
      'Incident: production issues are occurring right now (last 24h). ' ||
      'prod_issues_24h=' || d.prod_issues_24h::text ||
      '; last_prod_issue_at=' || coalesce(d.last_prod_issue_at::text, 'null') ||
      '; minutes_since_last_prod_issue=' || coalesce(d.minutes_since_last_prod_issue::text, 'null') ||
      '; severity_score_7d=' || d.severity_score_7d::text ||
      '; prod_issues_7d=' || d.prod_issues_7d::text

    when d.production_status = 'investigate' then
      'Investigate: elevated recent production risk (7d) or unclear cause. ' ||
      'prod_issues_24h=' || d.prod_issues_24h::text ||
      '; prod_issues_7d=' || d.prod_issues_7d::text ||
      '; last_prod_issue_at=' || coalesce(d.last_prod_issue_at::text, 'null') ||
      '; minutes_since_last_prod_issue=' || coalesce(d.minutes_since_last_prod_issue::text, 'null') ||
      '; severity_score_7d=' || d.severity_score_7d::text

    when d.production_status = 'watch' then
      'Watch: not active in last 24h, but there is recent history (7d). ' ||
      'prod_issues_24h=' || d.prod_issues_24h::text ||
      '; prod_issues_7d=' || d.prod_issues_7d::text ||
      '; last_prod_issue_at=' || coalesce(d.last_prod_issue_at::text, 'null') ||
      '; severity_score_7d=' || d.severity_score_7d::text

    else
      'OK: no production issues detected in the last 7 days. ' ||
      'prod_issues_7d=' || d.prod_issues_7d::text ||
      '; severity_score_7d=' || d.severity_score_7d::text
  end as status_reason,

  -- --------------------------
  -- action_hint (deterministic)
  -- --------------------------
  case
    when d.production_status = 'incident' then
      '1) Triage now: open logs/traces for the failing path. ' ||
      '2) Check the most recent deploy/config change. ' ||
      '3) Mitigate: rollback/feature-flag/scale/hotfix. ' ||
      '4) Post update when stable.'

    when d.production_status = 'investigate' then
      '1) Review recent deploys/flags and the top error signatures. ' ||
      '2) Confirm whether this is user-impacting. ' ||
      '3) Decide: fix today or monitor with a tight alert.'

    when d.production_status = 'watch' then
      '1) Monitor trends and keep alerts on. ' ||
      '2) If new issues appear, escalate to Investigate/Incident. ' ||
      '3) Consider follow-up work if repeated weekly.'

    else
      'No action needed. Keep monitoring.'
  end as action_hint
from public.v_production_decisions d;
