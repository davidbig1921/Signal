// ============================================================================
// File: src/lib/supabase/server.ts
// Project: Mercy Signal
// Purpose:
//   Supabase server client for Next.js App Router (Server Components safe).
// Notes:
//   - This client is SAFE to use in Server Components: it ONLY reads cookies.
//   - It does NOT attempt to set cookies (which would trigger Next warnings).
//   - Use a separate Route Handler / Server Action client if you need write-cookies.
// ============================================================================

import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

function mustGetEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

export async function createSupabaseServerClient() {
  const cookieStore = await cookies();

  const supabaseUrl = mustGetEnv("NEXT_PUBLIC_SUPABASE_URL");
  const supabaseAnonKey = mustGetEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");

  // Server Components: READ-ONLY cookies.
  // Setting cookies here causes:
  // "Cookies can only be modified in a Server Action or Route Handler"
  return createServerClient(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll().map((c) => ({
          name: c.name,
          value: c.value,
        }));
      },
      setAll() {
        // Intentionally no-op in Server Components.
        // If you need auth refresh that writes cookies, do it in middleware or a route handler.
      },
    },
  });
}
