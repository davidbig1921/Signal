begin;

create or replace function public.ms_suggested_action_text(p_code text)
returns text
language plpgsql
stable
as $$
declare
  normalized text;
  out_text text;
  has_domain_fn boolean;
  has_enum_fn boolean;
begin
  normalized := lower(trim(coalesce(p_code, '')));

  -- normalize unknowns safely
  if normalized not in ('monitor', 'investigate', 'page_oncall', 'noop') then
    normalized := 'noop';
  end if;

  -- CRITICAL: check for the FUNCTION overload, not just the TYPE
  has_domain_fn := to_regprocedure(
    'public.ms_suggested_action_text(public.ms_suggested_action_code_domain)'
  ) is not null;

  has_enum_fn := to_regprocedure(
    'public.ms_suggested_action_text(public.ms_suggested_action_code)'
  ) is not null;

  if has_domain_fn then
    execute
      'select public.ms_suggested_action_text(($1)::public.ms_suggested_action_code_domain)'
      into out_text
      using normalized;
    return out_text;

  elsif has_enum_fn then
    execute
      'select public.ms_suggested_action_text(($1)::public.ms_suggested_action_code)'
      into out_text
      using normalized;
    return out_text;

  else
    -- absolute fallback (never crash)
    -- keep it minimal + safe; only used if your locked overload is missing
    return case normalized
      when 'page_oncall' then 'Page on-call.'
      when 'investigate' then 'Investigate.'
      when 'monitor'     then 'Monitor.'
      else 'No action.'
    end;
  end if;
end;
$$;

commit;
