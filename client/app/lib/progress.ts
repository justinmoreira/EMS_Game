import { signal } from "@preact/signals";
import { authUser } from "./auth";
import { db } from "./db";
import { supabase } from "./supabase";

const isBrowser = typeof window !== "undefined";

export interface UserProgress {
  tutorial_complete: boolean;
}

export const progress = signal<UserProgress>({ tutorial_complete: false });

// Load from IndexedDB on startup
export async function initProgress() {
  if (!isBrowser) return;
  const row = await db.userProgress.get("self");
  if (row) {
    progress.value = { tutorial_complete: row.tutorial_complete };
  }
}

// Write to IndexedDB (instant), then sync to Supabase in background
export async function setProgress(updates: Partial<UserProgress>) {
  if (!isBrowser) return;
  const next = { ...progress.value, ...updates };
  progress.value = next;

  await db.userProgress.put({
    id: "self",
    tutorial_complete: next.tutorial_complete,
    updated_at: new Date().toISOString(),
    synced: false,
  });

  flushQueue();
}

// Push all unsynced rows to Supabase
async function flushQueue() {
  const user = authUser.value;
  if (!user) return;

  const unsynced = await db.userProgress.where("synced").equals(0).toArray();
  for (const row of unsynced) {
    try {
      await supabase.from("user_progress").upsert({
        user_id: user.id,
        tutorial_complete: row.tutorial_complete,
        updated_at: row.updated_at,
      });
      await db.userProgress.update(row.id, { synced: true });
    } catch {
      // Offline — stays in queue
      break;
    }
  }
}

// Pull from Supabase and merge (remote wins if newer)
async function pullFromDb() {
  const user = authUser.value;
  if (!user) return;

  try {
    const { data } = await supabase
      .from("user_progress")
      .select("tutorial_complete, updated_at")
      .eq("user_id", user.id)
      .maybeSingle();

    const local = await db.userProgress.get("self");
    const localTime = local?.updated_at ?? new Date(0).toISOString();

    if (data && data.updated_at > localTime) {
      // Remote is newer — update local
      await db.userProgress.put({
        id: "self",
        tutorial_complete: data.tutorial_complete,
        updated_at: data.updated_at,
        synced: true,
      });
      progress.value = { tutorial_complete: data.tutorial_complete };
    } else {
      // Local is newer or no remote — push local up
      flushQueue();
    }
  } catch {
    // Offline — local stays as truth
  }
}

// Sync on login and when coming back online
if (isBrowser) {
  initProgress();

  authUser.subscribe((user) => {
    if (user) pullFromDb();
  });

  window.addEventListener("online", () => {
    if (authUser.value) {
      pullFromDb();
      flushQueue();
    }
  });

  // Expose to Godot via JavaScriptBridge
  (window as unknown as Record<string, unknown>).getProgress = () =>
    JSON.stringify(progress.value);
  (window as unknown as Record<string, unknown>).setProgress = (json: string) =>
    setProgress(JSON.parse(json));

  // Notify Godot when progress changes (e.g. reset tutorial from Account modal)
  progress.subscribe((val) => {
    window.dispatchEvent(new CustomEvent("progress-changed", { detail: val }));
  });
}
