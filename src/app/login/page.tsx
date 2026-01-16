// ============================================================================
// File: src/app/login/page.tsx
// Version: 20260115-06-login-stub-ecosystem-auth-later
// Project: Mercy Signal
// Purpose:
//   Stub login page while Mercy ecosystem auth/payment/email are NOT wired.
// Notes:
//   - No magic link, no email flow.
//   - Explains why /decisions may show demo data (RLS requires auth.uid()).
//   - Keeps route stable for later ecosystem auth swap-in.
// ============================================================================

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const error = typeof sp.error === "string" ? sp.error : null;

  return (
    <main className="min-h-screen flex items-center justify-center px-6 bg-slate-50">
      <div className="w-full max-w-md rounded-2xl border bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-semibold text-slate-900">Sign in</h1>

        <p className="mt-2 text-sm text-slate-600">
          Mercy Signal will use the Mercy ecosystem authentication later.
          This screen is a placeholder for now.
        </p>

        {error ? (
          <div className="mt-4 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            {error}
          </div>
        ) : null}

        <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <div className="font-semibold">Why you might see demo data</div>
          <div className="mt-1 text-amber-800">
            Most live views are protected by RLS and require <span className="font-mono">auth.uid()</span>.
            Until ecosystem auth is wired, pages like <span className="font-mono">/decisions</span> may show
            a demo card instead of live rows.
          </div>
        </div>

        <div className="mt-5 rounded-xl bg-slate-50 p-4 text-xs text-slate-600">
          <div className="font-semibold text-slate-700">Dev-only note</div>
          <div className="mt-1">
            If you want live rows locally, you can temporarily use a dev user in Supabase Auth
            or add a dev-only read policy. We’re intentionally not committing to that flow here.
          </div>
        </div>

        <div className="mt-6 flex items-center justify-between">
          <a
            href="/decisions"
            className="inline-flex items-center justify-center rounded-xl bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
          >
            Back to Decisions
          </a>

          <a
            href="/"
            className="text-sm text-slate-600 hover:text-slate-900"
          >
            Home
          </a>
        </div>
      </div>
    </main>
  );
}
