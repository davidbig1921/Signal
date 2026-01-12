-- ============================================================================
-- File: supabase/migrations/202601102140_expose_v_production_decisions.sql
-- Version: 202601102140
-- Project: Mercy Signal
-- Purpose:
--   Expose production decision view as read-only to authenticated clients.
--
-- Notes:
--   - View is read-only by design
--   - RLS is enforced on underlying tables
--   - No writes are permitted
-- ============================================================================

begin;

-- Ensure view exists (no-op if already present)
-- (Do NOT create or replace here — ownership already established)

-- Allow authenticated users to read decisions
grant select
on public.v_production_decisions
to authenticated;

-- Optional: allow service role (safe)
grant select
on public.v_production_decisions
to service_role;

commit;
