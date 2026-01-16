// ============================================================================
// File: src/app/login/actions.ts
// Version: 20260115-02-fix-await-supabase-client-auth
// Project: Mercy Signal
// Purpose:
//   Server Actions for login (magic link).
// Notes:
//   - createSupabaseServerClient() returns a Promise -> must await before .auth
// ============================================================================

"use server";

import { headers } from "next/headers";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function signInWithMagicLink(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();

  if (!email) {
    return { ok: false as const, error: "Email is required." };
  }

  const supabase = await createSupabaseServerClient(); // ✅ IMPORTANT: await the client

  const h = await headers();
  const origin = h.get("origin") ?? "http://localhost:3000";

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: `${origin}/auth/callback`,
    },
  });

  if (error) {
    return { ok: false as const, error: error.message };
  }

  return { ok: true as const, error: null as string | null };
}
