import Link from "next/link"
import { getSignals } from "@/lib/data/signals"

export default async function SignalsPage() {
  const signals = await getSignals()

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Signals</h1>

        <Link
          href="/dashboard/signals/new"
          className="rounded border px-3 py-2 text-sm"
        >
          New
        </Link>
      </div>

      {/* Empty state */}
      {signals.length === 0 && (
        <p className="text-sm text-muted-foreground">
          No signals yet.
        </p>
      )}

      {/* List */}
      <ul className="space-y-2">
        {signals.map(signal => (
          <li
            key={signal.id}
            className="rounded border p-3"
          >
            <Link
              href={`/dashboard/signals/${signal.id}`}
              className="block space-y-1"
            >
              <div className="font-medium">{signal.title}</div>

              {signal.description && (
                <div className="text-sm text-muted-foreground">
                  {signal.description}
                </div>
              )}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}
