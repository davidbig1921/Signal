import { createServerClient } from "@/lib/supabase/server"
import { SignalEntry } from "@/lib/types/signal-entry"

export async function getEntriesForSignal(signalId: string): Promise<SignalEntry[]> {
  const supabase = await createServerClient()

  const { data, error } = await supabase
    .from("signal_entries")
    .select("*")
    .eq("signal_id", signalId)
    .order("created_at", { ascending: false })

  if (error) {
    console.error("Failed to fetch entries:", error)
    return []
  }

  return data as SignalEntry[]
}
