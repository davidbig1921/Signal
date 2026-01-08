import { createSignalAction } from "@/lib/actions/signals"

export default function NewSignalPage() {
  return (
    <div className="space-y-4 max-w-xl">
      <h1 className="text-xl font-semibold">New Signal</h1>

      <form action={createSignalAction} className="space-y-3">
        <div className="space-y-1">
          <label className="text-sm font-medium" htmlFor="title">
            Title
          </label>
          <input
            id="title"
            name="title"
            required
            minLength={3}
            maxLength={120}
            className="w-full rounded border px-3 py-2"
            placeholder="Short, clear title"
          />
        </div>

        <div className="space-y-1">
          <label className="text-sm font-medium" htmlFor="description">
            Description (optional)
          </label>
          <textarea
            id="description"
            name="description"
            maxLength={2000}
            className="w-full rounded border px-3 py-2 min-h-[120px]"
            placeholder="What happened? Why does it matter?"
          />
        </div>

        <button
          type="submit"
          className="rounded border px-4 py-2"
        >
          Create
        </button>
      </form>
    </div>
  )
}
