import { signInWithMagicLink } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const check = sp.check === "1";
  const error = typeof sp.error === "string" ? sp.error : null;

  return (
    <main className="min-h-screen flex items-center justify-center px-6 bg-slate-50">
      <div className="w-full max-w-md rounded-2xl border bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-semibold">Sign in</h1>
        <p className="mt-2 text-sm text-slate-600">
          We’ll email you a magic link. No password.
        </p>

        {check && (
          <div className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">
            Check your email for the sign-in link.
          </div>
        )}

        {error && (
          <div className="mt-4 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            {error}
          </div>
        )}

        <form action={signInWithMagicLink} className="mt-6 space-y-3">
          <label className="block text-sm font-medium text-slate-700">Email</label>
          <input
            name="email"
            type="email"
            placeholder="you@domain.com"
            required
            className="w-full rounded-xl border px-3 py-2 outline-none focus:ring"
          />

          <button
            type="submit"
            className="w-full rounded-xl bg-slate-900 px-3 py-2 text-white hover:bg-slate-800"
          >
            Send magic link
          </button>
        </form>
      </div>
    </main>
  );
}
