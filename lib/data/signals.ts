import { createServerClient } from "@/lib/supabase/server"
import { Signal } from "@/lib/types/signal"

export async function getSignals(): Promise<Signal[]> {
  const supabase = await createServerClient()

  const { data, error } = await supabase
    .from("signals")
    .select("*")
    .order("created_at", { ascending: false })

  if (error) {
    console.error("Failed to fetch signals:", error)
    return []
  }

  return data as Signal[]
}

export async function getSignalById(id: string): Promise<Signal | null> {
  const supabase = await createServerClient()

  const { data, error } = await supabase
    .from("signals")
    .select("*")
    .eq("id", id)
    .single()

  if (error) {
    // .single() returns an error when not found
    return null
  }

  return data as Signal
}
