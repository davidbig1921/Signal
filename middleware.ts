// Mercy Signal
// Version: v23
// File: middleware.ts
// Purpose:
//   - Keep Supabase auth session fresh (cookie refresh happens here).
//   - Guard /dashboard and /decisions routes (requires signed-in user).
//   - Prevent signed-in users from staying on /login.
// Notes:
//   - Middleware is allowed to set cookies.
//   - Server Components must be cookie read-only.
//   - Runs on /dashboard, /login, and /decisions so RLS pages stay authenticated.

import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

export async function middleware(req: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Fail-safe: if env is missing, do not crash middleware
  if (!url || !anon) return NextResponse.next();

  // Start with a normal pass-through response
  const res = NextResponse.next();

  // Supabase SSR client hooked to Next middleware cookies
  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll() {
        return req.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          res.cookies.set(name, value, options);
        }
      },
    },
  });

  // This call also refreshes session cookies when needed
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = req.nextUrl.pathname;

  const isProtected = path.startsWith("/dashboard") || path.startsWith("/decisions");

  // Protect dashboard + decisions
  if (isProtected && !user) {
    const redirectUrl = req.nextUrl.clone();
    redirectUrl.pathname = "/login";

    // Preserve any cookies we may have just set on res
    const redirectRes = NextResponse.redirect(redirectUrl);
    res.cookies.getAll().forEach((c) => redirectRes.cookies.set(c.name, c.value));
    return redirectRes;
  }

  // If already signed in, redirect away from /login
  if (path === "/login" && user) {
    const redirectUrl = req.nextUrl.clone();
    redirectUrl.pathname = "/dashboard/signals";

    const redirectRes = NextResponse.redirect(redirectUrl);
    res.cookies.getAll().forEach((c) => redirectRes.cookies.set(c.name, c.value));
    return redirectRes;
  }

  return res;
}

export const config = {
  matcher: ["/dashboard/:path*", "/login", "/decisions/:path*"],
};
