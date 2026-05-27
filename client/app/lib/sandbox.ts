// Sandbox state save/load — durable + cloud layer over the synchronous
// localStorage bridge that godot-bridge.js owns. The split exists so Godot's
// restore call on _ready never races this module's bundle load: window.
// saveSandbox / getSandbox come from godot-bridge.js (always present), and
// this module just observes the "sandbox-saved" event to fan out to Dexie +
// Supabase.
//
// Reusable surface for callers:
//   - currentSandbox      reactive signal of the live snapshot (JSON string)
//   - getCurrent()        synchronous localStorage read
//   - setCurrent(json)    write through localStorage → Dexie → Supabase (the
//                         Godot path normally fires this automatically via
//                         the "sandbox-saved" event)
//   - listSlots()         named slots for the saves menu
//   - saveAsSlot(name)    create: snapshot live state into a new named slot
//   - loadSlot(id)        read: promote a slot back to current (Godot
//                         restores on the next page load)
//   - overrideSlot(id)    update: overwrite an existing slot with live state
//   - deleteSlot(id)      delete
import { signal } from "@preact/signals";
import { authUser } from "./auth";
import { db, type SandboxStateRecord } from "./db";
import { supabase } from "./supabase";

const isBrowser = typeof window !== "undefined";
// Keep this in sync with godot-bridge.js's KEY constant.
const LS_KEY = "sandbox_current";
const CURRENT_ID = "current";
// Default mode tag for any caller that doesn't specify one. Lets the rest of
// the app stay mode-agnostic until a non-sandbox mode actually exists.
export const DEFAULT_GAMEMODE = "sandbox";

export interface SandboxSlot {
  id: string;
  name: string;
  gamemode: string;
  state_json: string;
  updated_at: string;
}

// ── localStorage layer (instant, always available) ──────────────────────

function readLocal(): string {
  if (!isBrowser) return "";
  return localStorage.getItem(LS_KEY) ?? "";
}

function writeLocal(json: string) {
  if (isBrowser) localStorage.setItem(LS_KEY, json);
}

export const currentSandbox = signal<string>(readLocal());

// ── Public API ──────────────────────────────────────────────────────────

export function getCurrent(): string {
  return readLocal();
}

export async function setCurrent(
  stateJson: string,
  gamemode: string = DEFAULT_GAMEMODE,
): Promise<void> {
  currentSandbox.value = stateJson;
  writeLocal(stateJson);
  await persistCurrent(stateJson, gamemode);
}

// Durable + cloud layer for the live snapshot. Called both directly from
// setCurrent (menu-driven writes) and from the "sandbox-saved" listener
// (Godot-driven auto-saves).
async function persistCurrent(
  stateJson: string,
  gamemode: string = DEFAULT_GAMEMODE,
): Promise<void> {
  if (!isBrowser) return;
  await db.sandboxStates.put({
    id: CURRENT_ID,
    name: "",
    gamemode,
    state_json: stateJson,
    updated_at: new Date().toISOString(),
    synced: false,
  });
  syncSlot(CURRENT_ID);
}

// listSlots filters by mode when one is passed (the picker UI calls it with
// the page's current mode); omitting the filter returns every named slot.
export async function listSlots(gamemode?: string): Promise<SandboxSlot[]> {
  if (!isBrowser) return [];
  const rows = await db.sandboxStates.toArray();
  return rows
    .filter(
      (r) =>
        r.id !== CURRENT_ID && (gamemode == null || r.gamemode === gamemode),
    )
    .sort((a, b) => (b.updated_at > a.updated_at ? 1 : -1))
    .map(toSlot);
}

export async function saveAsSlot(
  name: string,
  gamemode: string = DEFAULT_GAMEMODE,
): Promise<string> {
  if (!isBrowser) throw new Error("saveAsSlot called outside browser");
  const json = readLocal();
  if (!json) throw new Error("No live sandbox to snapshot");
  const id = crypto.randomUUID();
  await db.sandboxStates.put({
    id,
    name,
    gamemode,
    state_json: json,
    updated_at: new Date().toISOString(),
    synced: false,
  });
  syncSlot(id);
  return id;
}

// Overwrite an existing named slot's state with the current live snapshot.
// Keeps the slot's id and name; bumps updated_at so syncAll wins last-writer.
export async function overrideSlot(id: string): Promise<void> {
  if (!isBrowser || id === CURRENT_ID) {
    throw new Error("Cannot override the auto-save slot");
  }
  const existing = await db.sandboxStates.get(id);
  if (!existing) throw new Error("Slot not found");
  const json = readLocal();
  if (!json) throw new Error("No live sandbox to snapshot");
  await db.sandboxStates.put({
    id,
    name: existing.name,
    gamemode: existing.gamemode,
    state_json: json,
    updated_at: new Date().toISOString(),
    synced: false,
  });
  syncSlot(id);
}

export async function loadSlot(id: string): Promise<string | null> {
  if (!isBrowser) return null;
  const row = await db.sandboxStates.get(id);
  if (!row) return null;
  // Promote the slot's state to "current" so Godot picks it up via its
  // normal restore path on the next page load. Carry the slot's mode through
  // — loading a "mission" save into current should keep the mode tag.
  await setCurrent(row.state_json, row.gamemode);
  window.dispatchEvent(
    new CustomEvent("sandbox-loaded", { detail: { json: row.state_json } }),
  );
  return row.state_json;
}

export async function deleteSlot(id: string): Promise<void> {
  if (!isBrowser || id === CURRENT_ID) return;
  await db.sandboxStates.delete(id);
  const user = authUser.value;
  if (user) {
    try {
      await supabase
        .from("sandbox_states")
        .delete()
        .match({ user_id: user.id, slot_id: id });
    } catch {
      // best-effort; row stays remote, gone locally
    }
  }
}

// ── Sign-in conflict resolution ─────────────────────────────────────────

// If the user played anonymously, Dexie holds a `current` row that didn't go
// to any cloud account. After sign-in, syncAll's pull phase will overwrite
// that row with whatever the user's cloud `current` says — which would lose
// their anon work. Promote it to a named slot first so it survives, then
// mark the original current as already-synced so we don't push it up and
// stomp on the cloud current either.
async function promoteAnonOnSignIn(): Promise<void> {
  if (!isBrowser) return;
  const anon = await db.sandboxStates.get(CURRENT_ID);
  if (!anon || anon.synced) return;

  const newId = crypto.randomUUID();
  const stamp = new Date().toLocaleString();
  await db.sandboxStates.put({
    id: newId,
    name: `Pre-signup save (${stamp})`,
    gamemode: anon.gamemode || DEFAULT_GAMEMODE,
    state_json: anon.state_json,
    updated_at: anon.updated_at,
    synced: false,
  });
  await db.sandboxStates.update(CURRENT_ID, { synced: true });
}

// ── Sync (Supabase, background) ─────────────────────────────────────────

async function syncSlot(id: string): Promise<void> {
  const user = authUser.value;
  if (!user || !isBrowser) return;
  const row = await db.sandboxStates.get(id);
  if (!row) return;
  try {
    await supabase.from("sandbox_states").upsert({
      user_id: user.id,
      slot_id: id,
      name: row.name,
      gamemode: row.gamemode,
      state_json: row.state_json,
      updated_at: row.updated_at,
    });
    await db.sandboxStates.update(id, { synced: true });
  } catch {
    // Leave synced=false; next syncAll() picks it up.
  }
}

async function syncAll(): Promise<void> {
  const user = authUser.value;
  if (!user || !isBrowser) return;
  // Push anything we haven't pushed yet.
  const unsynced = await db.sandboxStates.where("synced").equals(0).toArray();
  for (const row of unsynced) {
    await syncSlot(row.id);
  }
  // Pull remote rows (last-writer-wins by updated_at).
  try {
    const { data } = await supabase
      .from("sandbox_states")
      .select("slot_id, name, gamemode, state_json, updated_at")
      .eq("user_id", user.id);
    if (!data) return;
    for (const r of data) {
      const local = await db.sandboxStates.get(r.slot_id);
      if (!local || r.updated_at > local.updated_at) {
        await db.sandboxStates.put({
          id: r.slot_id,
          name: r.name,
          gamemode: r.gamemode ?? DEFAULT_GAMEMODE,
          state_json: r.state_json,
          updated_at: r.updated_at,
          synced: true,
        });
        if (r.slot_id === CURRENT_ID) {
          currentSandbox.value = r.state_json;
          writeLocal(r.state_json);
        }
      }
    }
  } catch {
    // Offline / RLS rejection — silently skip; next attempt will retry.
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────

function toSlot(r: SandboxStateRecord): SandboxSlot {
  return {
    id: r.id,
    name: r.name,
    gamemode: r.gamemode ?? DEFAULT_GAMEMODE,
    state_json: r.state_json,
    updated_at: r.updated_at,
  };
}

// ── Lifecycle ───────────────────────────────────────────────────────────

if (isBrowser) {
  // On sign-in: rescue any anon work (so it doesn't get clobbered by the
  // user's cloud `current` during syncAll's pull phase), then sync.
  authUser.subscribe((user) => {
    if (!user) return;
    void promoteAnonOnSignIn().then(() => syncAll());
  });
  window.addEventListener("online", () => syncAll());

  // Observe godot-bridge.js's saves and fan out to Dexie + Supabase. The
  // localStorage write already happened in the bridge — we just need to add
  // the durable + cloud layers. Mode tag comes through the event detail so
  // each persisting scene controls its own slot namespace.
  window.addEventListener("sandbox-saved", (e) => {
    const detail = (e as CustomEvent<{ json: string; mode?: string }>).detail;
    const json = detail?.json ?? "";
    const mode = detail?.mode ?? DEFAULT_GAMEMODE;
    currentSandbox.value = json;
    void persistCurrent(json, mode);
  });

  // If a snapshot was already in localStorage at module load, sync our signal.
  const initial = readLocal();
  if (initial) currentSandbox.value = initial;
}
