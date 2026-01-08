import { supabaseServer } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import SignOutButton from "./signout-button";

export default async function DashboardPage() {
  const supabase = supabaseServer();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  return (
    <main className="min-h-screen p-8">
      <div className="mx-auto max-w-3xl space-y-6">
        <header className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold">Dashboard</h1>
            <p className="text-sm opacity-70">
              Signed in as <span className="font-medium">{user.email}</span>
            </p>
          </div>
          <SignOutButton />
        </header>

        <section className="rounded-2xl border p-6">
          <h2 className="text-lg font-semibold">Mercy Signal</h2>
          <p className="mt-1 text-sm opacity-70">
            v09: Auth guard + protected dashboard is working.
          </p>
        </section>
      </div>
    </main>
  );
}
