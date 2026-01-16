export default function Loading() {
  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-8 animate-pulse">
      <div className="h-7 w-64 rounded-lg bg-slate-200" />
      <div className="mt-2 h-4 w-96 rounded bg-slate-200" />

      <div className="mt-6 grid grid-cols-2 gap-4">
        <div className="h-24 rounded-2xl border border-slate-200 bg-white" />
        <div className="h-24 rounded-2xl border border-slate-200 bg-white" />
      </div>

      <div className="mt-6 space-y-4">
        <div className="h-32 rounded-2xl border border-slate-200 bg-white" />
        <div className="h-48 rounded-2xl border border-slate-200 bg-white" />
      </div>
    </div>
  );
}
