begin;

create or replace view public.v_active_decision_logic_version as
select
  v.id as decision_version_id,
  v.description as decision_version_description
from public.ms_decision_logic_version v
where v.is_active = true
order by v.id desc
limit 1;

grant select on public.v_active_decision_logic_version to authenticated;

commit;
