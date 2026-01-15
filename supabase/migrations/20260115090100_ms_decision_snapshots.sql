begin;

create table public.ms_decision_snapshots (
  id uuid primary key default gen_random_uuid(),

  signal_id uuid not null,

  -- frozen outputs
  production_status public.ms_production_status_domain not null,
  severity_label public.ms_severity_label_domain not null,
  confidence public.ms_confidence_label_domain not null,
  trend_24h_vs_7d public.ms_trend_label_domain,

  suggested_action_code public.ms_suggested_action_code_domain not null,
  status_reason_code public.ms_status_reason_code_domain not null,

  -- provenance
  logic_version text not null
    references public.ms_decision_logic_version(id),

  computed_at timestamptz not null default now(),

  -- safety
  unique (signal_id, logic_version)
);

create index on public.ms_decision_snapshots (signal_id);
create index on public.ms_decision_snapshots (computed_at);

grant select on public.ms_decision_snapshots to authenticated;

commit;
