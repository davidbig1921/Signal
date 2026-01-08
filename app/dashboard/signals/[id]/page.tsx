import Link from "next/link"
import { notFound } from "next/navigation"
import { getSignalById } from "@/lib/data/signals"
import { getEntriesForSignal } from "@/lib/data/signal-entries"
import {
  createSignalEntryAction,
  deleteSignalEntryAction,
} from "@/lib/actions/signal-entries"

function errorMessage(code?: string) {
  switch (code) {
    case "body_too_short":
      return "Entry must be at least 3 characters."
    case "body_too_long":
      return "Entry must be 5000 characters or less."
    case "source_too_long":
      return "Source must be 200 characters or less."
    case "insert_failed":
      return "Failed to add entry."
    case "delete_failed":
      return "Failed to delete entry."
    default:
      return null
  }
}

export default async function SignalDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams?: Promise<{ error?: string }>
}) {
  const { id } = await params
  const sp = searchParams ? await searchParams : undefined

  const signal = await getSignalById(id)
  if (!signal) notFound()

  const entries = await getEntriesForSignal(id)
  const err = errorMessage(sp?.error)

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">{signal.title}</h1>

        <Link
          href="/dashboard/signals"
          className="rounded border px-3 py-2 text-sm"
        >
          Back
        </Link>
      </div>

      {signal.description ? (
        <p className="text-sm text-muted-foreground whitespace-pre-wrap">
          {signal.description}
        </p>
      ) : (
        <p className="text-sm text-muted-foreground">No description.</p>
      )}

      <div className="text-xs text-muted-foreground">
        Created: {new Date(signal.created_at).toLocaleString()}
      </div>

      {/* Add Entry */}
      <div className="space-y-3 rounded border p-3">
        <h2 className="text-base font-semibold">Add entry</h2>

        {err && <p className="text-sm text-red-600">{err}</p>}

        <form action={createSignalEntryAction} className="space-y-3">
          <input type="hidden" name="signal_id" value={id} />

          <div className="space-y-1">
            <label className="text-sm font-medium" htmlFor="body">
              Entry
            </label>
            <textarea
              id="body"
              name="body"
              required
              minLength={3}
              maxLength={5000}
              className="w-full rounded border px-3 py-2 min-h-[120px]"
              placeholder="What happened? What did you observe?"
            />
          </div>

          <div className="space-y-1">
            <label className="text-sm font-medium" htmlFor="source">
              Source (optional)
            </label>
            <input
              id="source"
              name="source"
              maxLength={200}
              className="w-full rounded border px-3 py-2"
              placeholder="e.g. customer call, email, meeting"
            />
          </div>

          <button type="submit" className="rounded border px-4 py-2">
            Add
          </button>
        </form>
      </div>

      {/* Entries */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold">Entries</h2>
          <span className="text-xs text-muted-foreground">
            {entries.length} total
          </span>
        </div>

        {entries.length === 0 ? (
          <p className="text-sm text-muted-foreground">No entries yet.</p>
        ) : (
          <ul className="space-y-2">
            {entries.map((e) => (
              <li key={e.id} className="rounded border p-3 space-y-2">
                <div className="text-sm whitespace-pre-wrap">{e.body}</div>

                <div className="flex items-center justify-between text-xs text-muted-foreground gap-3">
                  <div className="flex items-center gap-3">
                    <span>
                      {e.source ? `Source: ${e.source}` : "Source: (none)"}
                    </span>
                    <span>{new Date(e.created_at).toLocaleString()}</span>
                  </div>

                  <form action={deleteSignalEntryAction}>
                    <input type="hidden" name="entry_id" value={e.id} />
                    <input type="hidden" name="signal_id" value={id} />
                    <button type="submit" className="underline">
                      Delete
                    </button>
                  </form>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
