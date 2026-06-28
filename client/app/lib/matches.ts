// Lobby lifecycle helpers shared by the lobby browser and the match page.
//
// A match id IS its shareable short code (the matches table keys on text), and
// every match also carries a separate invite_code used by the "join by code"
// box and private-match links. Both are drawn from an unambiguous alphabet
// (no 0/O/1/I) so they're safe to read aloud or type.
import type { Tables } from "./database.types";
import { supabase } from "./supabase";

export type Match = Tables<"matches">;

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function randomCode(len = 6): string {
  const out: string[] = [];
  const buf = new Uint32Array(len);
  crypto.getRandomValues(buf);
  for (let i = 0; i < len; i++)
    out.push(CODE_ALPHABET[buf[i] % CODE_ALPHABET.length]);
  return out.join("");
}

export interface CreateMatchOpts {
  name: string;
  visibility: "public" | "private";
  hostId: string;
}

// Insert a fresh lobby with the caller as host. Retries on the (tiny) chance
// of an id/invite_code collision before surfacing an error.
export async function createMatch(opts: CreateMatchOpts): Promise<Match> {
  const seed = Math.floor(Math.random() * 0x7fffffff);
  let lastErr = "";
  for (let attempt = 0; attempt < 5; attempt++) {
    const id = randomCode(6);
    const invite_code = randomCode(6);
    const { data, error } = await supabase
      .from("matches")
      .insert({
        id,
        seed,
        host_id: opts.hostId,
        status: "waiting",
        name: opts.name.trim() || "Match",
        visibility: opts.visibility,
        invite_code,
      })
      .select()
      .single();
    if (!error && data) return data;
    lastErr = error?.message ?? "unknown error";
    if (error && !/duplicate key|unique|already exists/i.test(error.message)) {
      throw new Error(lastErr);
    }
  }
  throw new Error(`Could not create a unique lobby (${lastErr}).`);
}

// Claim the empty guest seat via the join_match RPC (SECURITY DEFINER), which
// can reach a PRIVATE lobby the tightened SELECT policy hides from the client.
// Accepts a lobby id or an invite code (both are uppercase A-Z2-9). Returns the
// joined match id so the caller can navigate in. Race-safe: the seat fill is a
// single conditional UPDATE inside the function, not a read-modify-write.
export async function joinMatch(
  idOrCode: string,
): Promise<{ ok: boolean; matchId?: string; error?: string }> {
  const { data, error } = await supabase.rpc("join_match", {
    p_id_or_code: idOrCode.trim().toUpperCase(),
  });
  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "That seat was just taken." };
  return { ok: true, matchId: data as string };
}

export async function findByInvite(code: string): Promise<Match | null> {
  const trimmed = code.trim().toUpperCase();
  if (!trimmed) return null;
  // Match against the invite code OR the raw match id, so a pasted link/id
  // works in the same box.
  const byCode = await supabase
    .from("matches")
    .select("*")
    .eq("invite_code", trimmed)
    .maybeSingle();
  if (byCode.data) return byCode.data;
  const byId = await supabase
    .from("matches")
    .select("*")
    .eq("id", trimmed)
    .maybeSingle();
  return byId.data;
}

export async function listOpenPublicMatches(): Promise<Match[]> {
  const { data } = await supabase
    .from("matches")
    .select("*")
    .eq("visibility", "public")
    .in("status", ["waiting", "active"])
    .order("created_at", { ascending: false })
    .limit(50);
  return data ?? [];
}

export function playUrl(base: string, matchId: string): string {
  return `${base}/multiplayer/play?id=${encodeURIComponent(matchId)}`;
}
