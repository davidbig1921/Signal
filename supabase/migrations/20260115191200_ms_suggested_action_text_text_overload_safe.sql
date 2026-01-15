begin;

-- Safe text overload: never casts, never calls itself, never crashes.
create or replace function public.ms_suggested_action_text(p_code text)
returns text
language sql
stable
as $$
  select case lower(trim(coalesce(p_code,'')))
    when 'monitor' then 'Monitor the signal. Confirm impact, watch for worsening.'
    when 'investigate' then 'Investigate now. Identify source, confirm scope, prepare mitigation.'
    when 'page_oncall' then 'Page on-call. Treat as incident until proven otherwise.'
    else 'No action.'
  end;
$$;

commit;
