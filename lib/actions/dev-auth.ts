"use server"

import { redirect } from "next/navigation"
import { createServerClient } from "@/lib/supabase/server"

export async function devSignInAction() {
  if (process.env.MERCY_DEV_BYPASS_AUTH !== "true") {
    return redirect("/login")
  }

  const email = process.env.MERCY_DEV_EMAIL
  const password = process.env.MERCY_DEV_PASSWORD

  if (!email || !password) {
    return redirect("/login?error=missing_dev_env")
  }

  const supabase = await createServerClient()

  const { error } = await supabase.auth.signInWithPassword({
    email,
    password,
  })

  if (error) {
    console.error("devSignInAction failed:", error)
    return redirect(`/login?error=${encodeURIComponent(error.message)}`)
  }

  redirect("/dashboard/signals")
}
