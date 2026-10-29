"use client";

import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/lib/types";

export async function getSessionUser() {
  const sb = createClient();
  const { data } = await sb.auth.getSession();
  return data.session?.user ?? null;
}

/** Prefer RPC is_admin() (SECURITY DEFINER → profiles.is_admin). Fall back to a direct profiles select if the RPC is not migrated yet. Never trust JWT app_metadata. */
export async function fetchIsAdmin(userId: string): Promise<boolean> {
  const sb = createClient();
  const { data: rpcData, error: rpcError } = await sb.rpc("is_admin");
  if (!rpcError && typeof rpcData === "boolean") return rpcData;

  const { data } = await sb
    .from("profiles")
    .select("is_admin")
    .eq("id", userId)
    .maybeSingle();
  return Boolean((data as Profile | null)?.is_admin);
}

export async function fetchOwnProfile(userId: string): Promise<Profile | null> {
  const sb = createClient();
  const { data } = await sb
    .from("profiles")
    .select("id, display_name, avatar_url, is_admin")
    .eq("id", userId)
    .maybeSingle();
  return (data as Profile | null) ?? null;
}
