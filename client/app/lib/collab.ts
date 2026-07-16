// Lobby lifecycle helpers for collaborative sandbox rooms — the co-op analogue
// of matches.ts. A room id IS its shareable short code, and each room also
// carries a separate invite_code for the "join by code" box and private-room
// links. Both use the same unambiguous alphabet (no 0/O/1/I) as matches.
//
// Unlike a 1v1 match there's no turn/action table: live edits ride a Realtime
// broadcast channel (see CoopRoom.tsx), and the durable shared board lives in
// collab_rooms.state_json, upserted here.
import type { Json, Tables } from "./database.types";
import { randomCode } from "./matches";
import { supabase } from "./supabase";

export type CollabRoom = Tables<"collab_rooms">;

export interface CreateRoomOpts {
  name: string;
  visibility: "public" | "private";
  hostId: string;
}

// Insert a fresh room with the caller as host. Retries on the (tiny) chance of
// an id/invite_code collision before surfacing an error. Seed drives the shared
// terrain (same value read by both clients), exactly like matches.
export async function createRoom(opts: CreateRoomOpts): Promise<CollabRoom> {
  const seed = Math.floor(Math.random() * 0x7fffffff);
  let lastErr = "";
  for (let attempt = 0; attempt < 5; attempt++) {
    const id = randomCode(6);
    const invite_code = randomCode(6);
    const { data, error } = await supabase
      .from("collab_rooms")
      .insert({
        id,
        seed,
        host_id: opts.hostId,
        status: "waiting",
        name: opts.name.trim() || "Sandbox",
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
  throw new Error(`Could not create a unique room (${lastErr}).`);
}

// Claim the empty guest seat via the join_collab RPC (SECURITY DEFINER), which
// can reach a PRIVATE room the tightened SELECT policy hides. Accepts a room id
// or an invite code. Returns the joined room id. Race-safe: the seat fill is a
// single conditional UPDATE inside the function.
export async function joinRoom(
  idOrCode: string,
): Promise<{ ok: boolean; roomId?: string; error?: string }> {
  const { data, error } = await supabase.rpc("join_collab", {
    p_id_or_code: idOrCode.trim().toUpperCase(),
  });
  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "That room was just taken." };
  return { ok: true, roomId: data as string };
}

export async function findByInvite(code: string): Promise<CollabRoom | null> {
  const trimmed = code.trim().toUpperCase();
  if (!trimmed) return null;
  // Match the invite code OR the raw room id, so a pasted link/id works in the
  // same box.
  const byCode = await supabase
    .from("collab_rooms")
    .select("*")
    .eq("invite_code", trimmed)
    .maybeSingle();
  if (byCode.data) return byCode.data;
  const byId = await supabase
    .from("collab_rooms")
    .select("*")
    .eq("id", trimmed)
    .maybeSingle();
  return byId.data;
}

export async function listOpenPublicRooms(): Promise<CollabRoom[]> {
  const { data } = await supabase
    .from("collab_rooms")
    .select("*")
    .eq("visibility", "public")
    .in("status", ["waiting", "active"])
    .order("created_at", { ascending: false })
    .limit(50);
  return data ?? [];
}

// Upsert the durable shared board. Called (debounced) by the room page so a
// reload or late joiner can restore the scene. Either participant may write it
// (RLS allows both); in practice CoopRoom.tsx elects the host to avoid dueling
// writers. `updated_at` is bumped by the on_collab_rooms_updated trigger.
export async function persistSnapshot(
  roomId: string,
  stateJson: Json,
): Promise<void> {
  await supabase
    .from("collab_rooms")
    .update({ state_json: stateJson })
    .eq("id", roomId);
}

export async function deleteRoom(roomId: string): Promise<void> {
  await supabase.from("collab_rooms").delete().eq("id", roomId);
}

export function playUrl(base: string, roomId: string): string {
  return `${base}/coop/play?id=${encodeURIComponent(roomId)}`;
}
