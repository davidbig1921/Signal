"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@supabase/supabase-js";

export default function LoginPage() {
  const router = useRouter();

  const supabase = useMemo(() => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!url || !anon) {
      // Clear error message instead of a weird runtime crash
      throw new Error(
        "Missing Supabase env vars. Check .env.local for NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY, then restart `npm run dev`."
      );
    }

    // Force browser fetch
    return createClient(url, anon, {
      global: {
        fetch: (...args) => fetch(...args),
      },
    });
  }, []);

  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    setLoading(true);

    try {
      const { error } =
        mode === "signin"
          ? await supabase.auth.signInWithPassword({ email, password })
          : await supabase.auth.signUp({ email, password });

      if (error) return setErr(error.message);

      router.push("/dashboard");
      router.refresh();
    } catch (e: any) {
      setErr(e?.message ?? "Unknown error");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-6">
      <form
        className="w-full max-w-sm rounded-2xl border p-6 space-y-4"
        onSubmit={onSubmit}
      >
        <h1 className="text-xl font-semibold">Mercy Signal</h1>

        <div className="space-y-1">
          <label className="text-sm opacity-80">Email</label>
          <input
            className="w-full rounded-xl border px-3 py-2 bg-transparent"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@org.com"
            required
            autoComplete="email"
          />
        </div>

        <div className="space-y-1">
          <label className="text-sm opacity-80">Password</label>
          <input
            className="w-full rounded-xl border px-3 py-2 bg-transparent"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            type="password"
            required
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
          />
        </div>

        {err && <p className="text-sm text-red-500">{err}</p>}

        <button
          className="w-full rounded-xl border px-3 py-2 disabled:opacity-60"
          disabled={loading}
        >
          {loading ? "Please wait..." : mode === "signin" ? "Sign in" : "Sign up"}
        </button>

        <button
          type="button"
          className="w-full text-sm underline opacity-80"
          onClick={() => setMode(mode === "signin" ? "signup" : "signin")}
        >
          {mode === "signin" ? "Need an account? Sign up" : "Have an account? Sign in"}
        </button>
      </form>
    </main>
  );
}
