begin;

-- Expand allowed "kind" values
alter table public.signal_entries
  drop constraint if exists signal_entries_kind_check;

alter table public.signal_entries
  add constraint signal_entries_kind_check
  check (
    kind = any (
      array[
        'note',
        'observation',
        'question',
        'risk',
        'production_issue'
      ]::text[]
    )
  );

-- Expand allowed "area" values
alter table public.signal_entries
  drop constraint if exists signal_entries_area_check;

alter table public.signal_entries
  add constraint signal_entries_area_check
  check (
    area is null
    or area = any (
      array[
        'line',
        'machine',
        'api',
        'production'
      ]::text[]
    )
  );

commit;
