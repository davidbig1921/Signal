// ============================================================================
// File: src/lib/supabase/server.ts
// Version: 20260112-08
// Project: Mercy Signal
// Purpose:
//   Create a Supabase client for Next.js App Router Server Components.
// Notes:
//   - Cookie store API varies across Next/Turbopack builds.
//   - This adapter must NEVER throw.
// ============================================================================

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";

type CookieLike = { name: string; value: string };

function safeGetAllCookies(cookieStore: any): CookieLike[] {
  try {
    if (cookieStore && typeof cookieStore.getAll === "function") {
      return cookieStore.getAll();
    }
  } catch {
    // ignore
  }

  // Fallback: best-effort extraction for common Supabase cookie names.
  const names = [
    "sb-access-token",
    "sb-refresh-token",
    "sb-auth-token",
    "supabase-auth-token",
  ];

  const out: CookieLike[] = [];
  for (const name of names) {
    try {
      const c = cookieStore?.get?.(name);
      if (c?.value) out.push({ name, value: c.value });
    } catch {
      // ignore
    }
  }
  return out;
}

export function createSupabaseServerClient() {
  const cookieStore = cookies();

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return safeGetAllCookies(cookieStore);
      },
      setAll() {
        // no-op in Server Components
      },
    },
  });
}
