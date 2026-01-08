"use server"

import { redirect } from "next/navigation"
import { createServerClient } from "@/lib/supabase/server"

function clean(v: FormDataEntryValue | null) {
  return typeof v === "string" ? v.trim() : ""
}

export async function createSignalEntryAction(formData: FormData) {
  const signalId = clean(formData.get("signal_id"))
  const body = clean(formData.get("body"))
  const sourceRaw = clean(formData.get("source"))
  const source = sourceRaw.length > 0 ? sourceRaw : null

  // minimal validation
  if (!signalId) {
    return redirect(`/dashboard/signals?error=missing_signal`)
  }
  if (!body || body.length < 3) {
    return redirect(`/dashboard/signals/${signalId}?error=body_too_short`)
  }
  if (body.length > 5000) {
    return redirect(`/dashboard/signals/${signalId}?error=body_too_long`)
  }
  if (source && source.length > 200) {
    return redirect(`/dashboard/signals/${signalId}?error=source_too_long`)
  }

  const supabase = await createServerClient()
  const { data: auth, error: authError } = await supabase.auth.getUser()

  if (authError || !auth.user) {
    return redirect(`/login`)
  }

  const { error } = await supabase.from("signal_entries").insert({
    signal_id: signalId,
    body,
    source,
    created_by: auth.user.id,
  })

  if (error) {
    console.error("createSignalEntryAction insert failed:", error)
    return redirect(`/dashboard/signals/${signalId}?error=insert_failed`)
  }

  redirect(`/dashboard/signals/${signalId}`)
}

export async function deleteSignalEntryAction(formData: FormData) {
  const entryId = clean(formData.get("entry_id"))
  const signalId = clean(formData.get("signal_id"))

  if (!entryId || !signalId) {
    return redirect("/dashboard/signals?error=missing_params")
  }

  const supabase = await createServerClient()
  const { data: auth, error: authError } = await supabase.auth.getUser()

  if (authError || !auth.user) {
    return redirect("/login")
  }

  const { error } = await supabase
    .from("signal_entries")
    .delete()
    .eq("id", entryId)

  if (error) {
    console.error("deleteSignalEntryAction failed:", error)
    return redirect(`/dashboard/signals/${signalId}?error=delete_failed`)
  }

  redirect(`/dashboard/signals/${signalId}`)
}
