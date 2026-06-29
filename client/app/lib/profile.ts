// Player profile + leaderboard layer.
//
// profiles rows are created server-side by the on_auth_user_created trigger
// (see 20260625000000_multiplayer_production.sql). This module keeps the
// row's display_name in sync with the account's metadata, mirrors it to the
// localStorage key the NavBar reads, and exposes the leaderboard query.
//
// Win/loss tallies are NEVER written from here — they move exclusively through
// the finish_match() RPC so a client can't inflate its own record.
import { signal } from "@preact/signals";
import type { User } from "@supabase/supabase-js";
import { authUser } from "./auth";
import type { Tables } from "./database.types";
import { supabase } from "./supabase";

export type Profile = Tables<"profiles">;

const isBrowser = typeof window !== "undefined";
const NAME_KEY = "account_display_name";

export const myProfile = signal<Profile | null>(null);

export function displayNameFor(
  user: Pick<User, "user_metadata" | "email">,
): string {
  return (
    (user.user_metadata?.display_name as string | undefined)?.trim() ||
    user.email?.split("@")[0] ||
    "Player"
  );
}

// Upsert the caller's display_name (keeps profiles in step with the account
// metadata edited in AuthPanel), then load the full row. Returns null when
// signed out or on error.
export async function ensureProfile(): Promise<Profile | null> {
  const user = authUser.value;
  if (!user) return null;
  const name = displayNameFor(user);
  try {
    // onConflict id → updates only display_name; tallies are untouched.
    await supabase
      .from("profiles")
      .upsert({ id: user.id, display_name: name }, { onConflict: "id" });
  } catch {
    // The row may already exist with this name, or we're offline — fall
    // through and just read whatever is there.
  }
  const { data } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();
  myProfile.value = data ?? null;
  if (data && isBrowser) {
    try {
      localStorage.setItem(NAME_KEY, data.display_name);
    } catch {
      // private mode / quota — non-fatal
    }
  }
  return data ?? null;
}

export async function getLeaderboard(limit = 100): Promise<Profile[]> {
  const { data } = await supabase
    .from("profiles")
    .select("*")
    .order("wins", { ascending: false })
    .order("losses", { ascending: true })
    .order("display_name", { ascending: true })
    .limit(limit);
  return data ?? [];
}

export async function getProfiles(
  ids: string[],
): Promise<Map<string, Profile>> {
  const map = new Map<string, Profile>();
  const unique = [...new Set(ids.filter(Boolean))];
  if (unique.length === 0) return map;
  const { data } = await supabase.from("profiles").select("*").in("id", unique);
  for (const p of data ?? []) map.set(p.id, p);
  return map;
}

if (isBrowser) {
  // Refresh the profile whenever the signed-in user changes.
  authUser.subscribe((user) => {
    if (user) void ensureProfile();
    else myProfile.value = null;
  });
}
