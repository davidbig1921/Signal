begin;

alter table public.ms_decision_logic_version
add column if not exists is_active boolean not null default false;

create unique index if not exists ms_decision_logic_single_active
on public.ms_decision_logic_version ((is_active))
where is_active = true;

commit;
