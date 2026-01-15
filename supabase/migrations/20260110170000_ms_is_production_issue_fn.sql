create or replace function public.is_production_issue(p_kind text, p_body text)
returns boolean
language sql
immutable
strict
as $$
  select
    (p_kind in ('production_issue', 'prod_issue', 'prod', 'incident'))
    or
    (
      p_kind in ('log', 'note', 'event', 'signal', 'other')
      and p_body is not null
      and (
        p_body ilike '%production%'
        or p_body ilike '%incident%'
        or p_body ilike '%outage%'
        or p_body ilike '%downtime%'
        or p_body ilike '%500%'
        or p_body ilike '%502%'
        or p_body ilike '%503%'
        or p_body ilike '%504%'
        or p_body ilike '%timeout%'
        or p_body ilike '%error%'
        or p_body ilike '%exception%'
      )
    );
$$;
