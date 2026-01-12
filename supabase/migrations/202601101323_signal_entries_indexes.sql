begin;

do $$
begin
  if to_regclass('public.signal_entries') is not null then
    create index if not exists signal_entries_signal_id_created_at_desc_idx
      on public.signal_entries (signal_id, created_at desc);

    create index if not exists signal_entries_signal_id_kind_created_at_desc_idx
      on public.signal_entries (signal_id, kind, created_at desc);
  end if;
end $$;

commit;
