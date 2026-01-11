// Mercy Signal
// Version: v21
// File: middleware.ts
// Purpose: Guard /dashboard with Supabase auth session (auth.uid() for RLS)
// Notes:
//   - Middleware is allowed to set cookies (session refresh happens here).
//   - Server Components must be read-only for cookies.
//   - Runs on /dashboard, /login, and /decisions so RLS pages stay authenticated.

import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

export async function middleware(req: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Fail-safe: if env is missing, do not crash middleware
  if (!url || !anon) {
    return NextResponse.next();
  }

  // IMPORTANT: include request headers so downstream can see refreshed cookies
  let res = NextResponse.next({
    request: { headers: req.headers },
  });

  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll() {
        return req.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) => {
          res.cookies.set(name, value, options);
        });
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = req.nextUrl.pathname;

  // Protect dashboard
  if (path.startsWith("/dashboard") && !user) {
    const redirectUrl = req.nextUrl.clone();
    redirectUrl.pathname = "/login";
    return NextResponse.redirect(redirectUrl);
  }

  // If already signed in, redirect away from /login
  if (path === "/login" && user) {
    const redirectUrl = req.nextUrl.clone();
    redirectUrl.pathname = "/dashboard/signals";
    return NextResponse.redirect(redirectUrl);
  }

  return res;
}

export const config = {
  matcher: ["/dashboard/:path*", "/login", "/decisions/:path*"],
};
