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
// Start "offline" — only flip to "online" once sync() actually succeeds.
// `navigator.onLine` says "network is up", not "Supabase round-trip succeeded".
export const syncStatus = signal<"online" | "offline" | "syncing">("offline");

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

// Sync: push unsynced Dexie rows to Supabase, pull remote if newer.
// Bails (and updates status) instead of throwing network errors when offline.
let syncInFlight = false;
let retryTimer: ReturnType<typeof setTimeout> | null = null;
let retryDelay = 2000;
const MAX_RETRY = 60_000;

function scheduleRetry() {
  if (retryTimer) clearTimeout(retryTimer);
  retryTimer = setTimeout(() => {
    retryTimer = null;
    sync();
  }, retryDelay);
  retryDelay = Math.min(retryDelay * 2, MAX_RETRY);
}

// Supabase healthcheck — drives the pill exclusively from Supabase reachability.
// Hits gotrue's /auth/v1/health which doesn't require an API key and returns
// 200 + JSON when the auth service is up.
const HEALTH_OK_INTERVAL = 30_000;
const HEALTH_MAX_BACKOFF = 60_000;
let healthTimer: ReturnType<typeof setTimeout> | null = null;
let healthBackoff = 2000;
let healthInFlight = false;

async function probeSupabase(): Promise<boolean> {
  if (!isBrowser || !navigator.onLine) return false;
  try {
    const url = `${import.meta.env.PUBLIC_SUPABASE_URL}/auth/v1/health`;
    const res = await fetch(url, { method: "GET", cache: "no-store" });
    return res.ok;
  } catch {
    return false;
  }
}

async function tickHealth() {
  if (healthInFlight) return;
  healthInFlight = true;
  try {
    const up = await probeSupabase();
    if (up) {
      healthBackoff = 2000;
      if (authUser.value) {
        // Signed in: run a sync to verify writes/reads round-trip and reflect
        // any unsynced local changes.
        sync();
      } else {
        syncStatus.value = "online";
      }
      scheduleHealth(HEALTH_OK_INTERVAL);
    } else {
      syncStatus.value = "offline";
      healthBackoff = Math.min(healthBackoff * 2, HEALTH_MAX_BACKOFF);
      scheduleHealth(healthBackoff);
    }
  } finally {
    healthInFlight = false;
  }
}

function scheduleHealth(delay: number) {
  if (healthTimer) clearTimeout(healthTimer);
  healthTimer = setTimeout(tickHealth, delay);
}

function startHealthProbe() {
  scheduleHealth(0);
}

function nudgeHealth() {
  healthBackoff = 2000;
  scheduleHealth(0);
}

async function sync() {
  if (!isBrowser || syncInFlight) return;
  const user = authUser.value;
  if (!user) {
    // No account → nothing to sync. Pill reflects pure connectivity.
    syncStatus.value = navigator.onLine ? "online" : "offline";
    return;
  }
  if (!navigator.onLine) {
    // Browser says we're offline — don't issue requests that will obviously
    // fail and spam the console. Wait for the `online` event.
    syncStatus.value = "offline";
    return;
  }

  syncInFlight = true;
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
    retryDelay = 2000;
  } catch {
    syncStatus.value = "offline";
    scheduleRetry();
  } finally {
    syncInFlight = false;
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
    else syncStatus.value = navigator.onLine ? "online" : "offline";
  });

  window.addEventListener("offline", () => {
    if (retryTimer) {
      clearTimeout(retryTimer);
      retryTimer = null;
    }
    syncStatus.value = "offline";
  });

  window.addEventListener("online", () => {
    retryDelay = 2000;
    sync();
  });

  startHealthProbe();

  // Godot bridge
  const w = window as unknown as Record<string, unknown>;
  w.getProgress = () => JSON.stringify(progress.value);
  w.setProgress = (json: string) => setProgress(JSON.parse(json));

  progress.subscribe((val) => {
    window.dispatchEvent(new CustomEvent("progress-changed", { detail: val }));
  });
}
