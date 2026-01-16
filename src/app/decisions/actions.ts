// ============================================================================
// File: src/app/decisions/actions.ts
// Purpose:
//   Server Actions for Decisions (kept tiny; page uses server-side fetching).
// Notes:
//   - createSupabaseServerClient() is async; MUST be awaited.
// ============================================================================

"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function listProductionDecisions() {
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("v_production_decisions")
    .select("*");

  if (error) {
    return { ok: false as const, data: [], error: error.message };
  }

  return { ok: true as const, data: data ?? [], error: null };
}
