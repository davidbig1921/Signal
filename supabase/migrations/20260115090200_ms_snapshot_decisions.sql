begin;

create or replace function public.ms_snapshot_current_decisions()
returns integer
language sql
security definer
as $$
  insert into public.ms_decision_snapshots (
    signal_id,
    production_status,
    severity_label,
    confidence,
    trend_24h_vs_7d,
    suggested_action_code,
    status_reason_code,
    logic_version
  )
  select
    d.signal_id,
    d.production_status,
    d.severity_label,
    d.confidence,
    d.trend_24h_vs_7d,
    d.suggested_action_code,
    d.status_reason_code,
    v.id as logic_version
  from public.v_production_decisions_explain d
  cross join public.ms_decision_logic_version v
  where v.id = (select max(id) from public.ms_decision_logic_version)
  on conflict do nothing;

  select count(*)::integer
  from public.ms_decision_snapshots
  where logic_version = (select max(id) from public.ms_decision_logic_version);
$$;

grant execute on function public.ms_snapshot_current_decisions to authenticated;

commit;
