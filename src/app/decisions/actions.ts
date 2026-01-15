"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function loadProductionDecisions() {
  const supabase = createSupabaseServerClient();

  const { data, error } = await supabase
    .from("v_production_decisions")
    .select("*")
    .order("production_status", { ascending: false });

  if (error) throw new Error(error.message);
  return data ?? [];
}
