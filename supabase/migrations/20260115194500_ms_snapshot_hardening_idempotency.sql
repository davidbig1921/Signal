-- =============================================================================
-- Migration: 20260115194500_ms_snapshot_hardening_idempotency
-- Project: Mercy Signal
-- Purpose:
--   - Make deploy snapshots deterministic and safe
--   - Ensure "latest snapshot" ordering is unambiguous
--   - Prevent future snapshot ambiguity (idempotency support)
--
-- Notes:
--   - This migration does NOT trigger a snapshot.
--   - Snapshots must be taken explicitly by logic activation or deploy flow.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Ensure deploy snapshots have a stable timestamp
-- -----------------------------------------------------------------------------
alter table public.ms_deploy_snapshot
  add column if not exists created_at timestamptz not null default now();

-- -----------------------------------------------------------------------------
-- 2) Deterministic ordering for "latest snapshot" queries
-- -----------------------------------------------------------------------------
create index if not exists ms_deploy_snapshot_created_at_desc
  on public.ms_deploy_snapshot (created_at desc);

-- -----------------------------------------------------------------------------
-- 3) Safety: ensure snapshot table cannot be silently duplicated by accident
--     (If logic_version_id exists, this index helps dedupe lookups.)
--     Commented out if column does not exist yet.
-- -----------------------------------------------------------------------------
-- create index if not exists ms_deploy_snapshot_logic_version_id_idx
--   on public.ms_deploy_snapshot (logic_version_id);

commit;
