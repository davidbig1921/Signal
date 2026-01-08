import { devSignInAction } from "@/lib/actions/dev-auth"

export default function DevPage() {
  return (
    <div className="max-w-md space-y-4">
      <h1 className="text-xl font-semibold">Dev Access</h1>
      <p className="text-sm text-muted-foreground">
        This bypass exists only when MERCY_DEV_BYPASS_AUTH=true.
      </p>

      <form action={devSignInAction}>
        <button className="rounded border px-4 py-2" type="submit">
          Enter Mercy Signal (Dev)
        </button>
      </form>
    </div>
  )
}
