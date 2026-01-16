// src/lib/entitlement.ts
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type MyEntitlement = {
  plan_code: string;
  status: string;
  starts_at: string | null;
  ends_at: string | null;
};

export async function fetchMyEntitlement(): Promise<MyEntitlement> {
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("v_my_entitlement")
    .select("plan_code, status, starts_at, ends_at")
    .limit(1)
    .maybeSingle();

  if (error || !data) {
    return { plan_code: "free", status: "active", starts_at: null, ends_at: null };
  }

  return {
    plan_code: data.plan_code ?? "free",
    status: data.status ?? "active",
    starts_at: data.starts_at ?? null,
    ends_at: data.ends_at ?? null,
  };
}

export function isPro(planCode: string | null | undefined): boolean {
  return (planCode ?? "free") !== "free";
}
