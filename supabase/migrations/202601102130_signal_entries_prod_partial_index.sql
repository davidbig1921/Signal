begin;

-- Helps v_production_decisions scan production issues fast
create index if not exists signal_entries_prod_recent_idx
on public.signal_entries (signal_id, created_at desc)
where
  (lower(kind) in ('risk','incident'))
  or (lower(severity) in ('high','critical'));

commit;
