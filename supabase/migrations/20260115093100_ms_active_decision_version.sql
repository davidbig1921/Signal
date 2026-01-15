begin;

create or replace view public.v_active_decision_logic_version as
select
  id as decision_version_id,
  description as decision_version_description,
  is_active,
  now() as fetched_at
from public.ms_decision_logic_version
where is_active = true
limit 1;

grant select on public.v_active_decision_logic_version to authenticated;

commit;
