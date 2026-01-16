-- =============================================================================
-- Migration: ms_profiles_entitlements
-- Purpose:
--   - Minimal entitlement layer (no payments/email yet)
--   - profiles table (optional)
--   - entitlements table (source of truth)
--   - view for current user's entitlement
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Optional profiles table (nice-to-have; not required for entitlements)
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  display_name text null
);

alter table public.profiles enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_select_own'
  ) then
    create policy profiles_select_own
      on public.profiles
      for select
      using (auth.uid() = id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_upsert_own'
  ) then
    create policy profiles_upsert_own
      on public.profiles
      for insert
      with check (auth.uid() = id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_update_own'
  ) then
    create policy profiles_update_own
      on public.profiles
      for update
      using (auth.uid() = id)
      with check (auth.uid() = id);
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- Entitlements (source of truth)
-- -----------------------------------------------------------------------------
create table if not exists public.entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  -- keep simple for now
  plan_code text not null check (plan_code in ('free','pro','team','enterprise')),
  status text not null check (status in ('active','trialing','paused','canceled','expired')),

  starts_at timestamptz not null default now(),
  ends_at timestamptz null,

  created_at timestamptz not null default now()
);

create index if not exists entitlements_user_id_idx on public.entitlements(user_id);
create index if not exists entitlements_user_active_idx
  on public.entitlements(user_id)
  where status in ('active','trialing');

alter table public.entitlements enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='entitlements' and policyname='entitlements_select_own'
  ) then
    create policy entitlements_select_own
      on public.entitlements
      for select
      using (auth.uid() = user_id);
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- View: current user's entitlement (single row)
-- -----------------------------------------------------------------------------
create or replace view public.v_my_entitlement as
select
  e.user_id,
  e.plan_code,
  e.status,
  e.starts_at,
  e.ends_at,
  (e.status in ('active','trialing') and (e.ends_at is null or e.ends_at > now())) as is_entitled
from public.entitlements e
where e.user_id = auth.uid()
order by
  (e.status in ('active','trialing')) desc,
  coalesce(e.ends_at, 'infinity'::timestamptz) desc,
  e.created_at desc
limit 1;

commit;
