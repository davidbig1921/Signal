create or replace view public.v_decision_snapshots as
select
  s.*,
  a.description as logic_description
from public.ms_decision_snapshots s
join public.ms_decision_logic_version a
  on a.id = s.logic_version;

grant select on public.v_decision_snapshots to authenticated;
