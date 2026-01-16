-- =============================================================================
-- Migration: ms_entitlement_seed_admin
-- Purpose:
--   - Seed one entitlement row for a real auth.users account (idempotent)
-- =============================================================================

begin;

do $$
declare
  v_user_id uuid;
begin
  select id
    into v_user_id
  from auth.users
  where lower(email) = lower('davidbig1921@gmail.com')
  limit 1;

  if v_user_id is null then
    raise notice 'No auth.users row found for email %, skipping seed.', 'davidbig1921@gmail.com';
    return;
  end if;

  insert into public.entitlements (user_id, plan_code, status, starts_at, ends_at)
  select v_user_id, 'pro', 'active', now(), null
  where not exists (
    select 1
    from public.entitlements e
    where e.user_id = v_user_id
      and e.status in ('active','trialing')
      and (e.ends_at is null or e.ends_at > now())
  );
end
$$;

commit;
