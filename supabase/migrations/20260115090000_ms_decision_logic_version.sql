begin;

create table if not exists public.ms_decision_logic_version (
  id text primary key,
  description text not null,
  applied_at timestamptz not null default now()
);

-- one active version (append-only over time)
insert into public.ms_decision_logic_version (id, description)
values ('v1', 'Initial production decision logic')
on conflict do nothing;

commit;
