import { signal } from "@preact/signals";
import { authUser } from "./auth";
import { db } from "./db";
import { supabase } from "./supabase";

const isBrowser = typeof window !== "undefined";
const LS_KEY = "user_progress";

export interface UserProgress {
  tutorial_complete: boolean;
}

// localStorage = instant read, always available
function readLocal(): UserProgress {
  if (!isBrowser) return { tutorial_complete: false };
  try {
    return JSON.parse(localStorage.getItem(LS_KEY) || "{}");
  } catch {
    return { tutorial_complete: false };
  }
}

function writeLocal(p: UserProgress) {
  if (isBrowser) localStorage.setItem(LS_KEY, JSON.stringify(p));
}

// Reactive state — initialized from localStorage (sync, instant)
export const progress = signal<UserProgress>(readLocal());
export const syncStatus = signal<"online" | "offline" | "syncing">(
  isBrowser && navigator.onLine ? "online" : "offline",
);

// Write: localStorage (instant) → Dexie (durable) → Supabase (background)
export async function setProgress(updates: Partial<UserProgress>) {
  const next = { ...progress.value, ...updates };
  progress.value = next;
  writeLocal(next);

  if (!isBrowser) return;

  await db.userProgress.put({
    id: "self",
    tutorial_complete: next.tutorial_complete,
    updated_at: new Date().toISOString(),
    synced: false,
  });

  sync();
}

// Sync: push unsynced Dexie rows to Supabase, pull remote if newer
async function sync() {
  const user = authUser.value;
  if (!user || !isBrowser) return;

  syncStatus.value = "syncing";

  try {
    // Push local changes
    const unsynced = await db.userProgress.where("synced").equals(0).toArray();
    for (const row of unsynced) {
      await supabase.from("user_progress").upsert({
        user_id: user.id,
        tutorial_complete: row.tutorial_complete,
        updated_at: row.updated_at,
      });
      await db.userProgress.update(row.id, { synced: true });
    }

    // Pull remote
    const { data } = await supabase
      .from("user_progress")
      .select("tutorial_complete, updated_at")
      .eq("user_id", user.id)
      .maybeSingle();

    if (data) {
      const local = await db.userProgress.get("self");
      if (!local || data.updated_at > local.updated_at) {
        const remote = { tutorial_complete: data.tutorial_complete };
        progress.value = remote;
        writeLocal(remote);
        await db.userProgress.put({
          id: "self",
          tutorial_complete: data.tutorial_complete,
          updated_at: data.updated_at,
          synced: true,
        });
      }
    }

    syncStatus.value = "online";
  } catch {
    syncStatus.value = "offline";
  }
}

// Lifecycle
if (isBrowser) {
  // Hydrate Dexie from localStorage on first load
  const local = readLocal();
  if (local.tutorial_complete) {
    db.userProgress.put({
      id: "self",
      tutorial_complete: local.tutorial_complete,
      updated_at: new Date().toISOString(),
      synced: false,
    });
  }

  authUser.subscribe((user) => {
    if (user) sync();
  });
  window.addEventListener("online", () => sync());
  window.addEventListener("offline", () => {
    syncStatus.value = "offline";
  });

  // Godot bridge
  const w = window as unknown as Record<string, unknown>;
  w.getProgress = () => JSON.stringify(progress.value);
  w.setProgress = (json: string) => setProgress(JSON.parse(json));

  progress.subscribe((val) => {
    window.dispatchEvent(new CustomEvent("progress-changed", { detail: val }));
  });
}
