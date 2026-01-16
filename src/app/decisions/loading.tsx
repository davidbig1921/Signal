// src/app/decisions/loading.tsx
export default function LoadingDecisions() {
  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-50">
      <div className="mx-auto max-w-5xl px-4 py-6">
        <div className="mb-4 h-7 w-64 animate-pulse rounded bg-neutral-800" />
        <div className="mb-6 h-4 w-96 animate-pulse rounded bg-neutral-900" />

        <div className="grid gap-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="rounded-2xl border border-neutral-800 bg-neutral-900/40 p-4"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="w-full">
                  <div className="mb-2 h-5 w-72 animate-pulse rounded bg-neutral-800" />
                  <div className="h-4 w-56 animate-pulse rounded bg-neutral-900" />
                </div>
                <div className="h-8 w-24 animate-pulse rounded-full bg-neutral-800" />
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <div className="h-7 w-24 animate-pulse rounded-full bg-neutral-800" />
                <div className="h-7 w-24 animate-pulse rounded-full bg-neutral-800" />
                <div className="h-7 w-24 animate-pulse rounded-full bg-neutral-800" />
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
