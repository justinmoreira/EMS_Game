import { useEffect, useState } from "preact/hooks";
import {
  DEFAULT_GAMEMODE,
  deleteSlot,
  listSlots,
  loadSlot,
  overrideSlot,
  type SandboxSlot,
  saveAsSlot,
} from "@/lib/sandbox";
import { BASE_URL } from "@/utils";

// Mode filter for the in-game picker. /sandbox is the only page that mounts
// this component, so we scope to "sandbox" saves. A future mission UI would
// mount its own picker instance with `gamemode="mission"` (or accept a prop).
const PICKER_MODE = DEFAULT_GAMEMODE;

// In-game saves modal — opened from Godot via `window.openSavesPicker()`.
// Mounts once via sandbox.astro; visibility is event-driven so Godot doesn't
// need to know about Preact internals (or vice versa).
//
// UX: click a row to select it; click again to deselect. The bottom toolbar
// (Load / Override / Delete) acts on the selected slot. Saving a new slot
// uses the inline name input + button at the top.

// godot-bridge.js owns window.openSavesPicker (it routes to either this
// event when signed in, or "open-auth-modal" when not). We just listen.
const OPEN_EVENT = "open-saves-picker";

export default function SavesPicker() {
  const [open, setOpen] = useState(false);
  const [slots, setSlots] = useState<SandboxSlot[]>([]);
  const [saveName, setSaveName] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    const handler = () => {
      refresh();
      setOpen(true);
    };
    window.addEventListener(OPEN_EVENT, handler);
    return () => window.removeEventListener(OPEN_EVENT, handler);
  }, []);

  // ESC closes — keyboard accessibility for the modal.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  async function refresh() {
    setSlots(await listSlots(PICKER_MODE));
  }

  function close() {
    setOpen(false);
    setErr("");
    setNotice("");
    setSaveName("");
    setSelectedId(null);
  }

  function toggleSelect(id: string) {
    setSelectedId((curr) => (curr === id ? null : id));
    setErr("");
    setNotice("");
  }

  function flashNotice(msg: string) {
    setNotice(msg);
    // Auto-clear so it doesn't linger across actions.
    window.setTimeout(() => setNotice(""), 2500);
  }

  async function onCreate() {
    const trimmed = saveName.trim();
    if (!trimmed) {
      setErr("Name required");
      return;
    }
    setBusy(true);
    setErr("");
    try {
      await saveAsSlot(trimmed, PICKER_MODE);
      setSaveName("");
      await refresh();
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function onLoad() {
    if (!selectedId) return;
    setBusy(true);
    try {
      await loadSlot(selectedId);
      window.location.href = `${BASE_URL}/sandbox`;
    } finally {
      setBusy(false);
    }
  }

  async function onOverride() {
    if (!selectedId) return;
    const target = slots.find((s) => s.id === selectedId);
    const label = target?.name || "this save";
    if (
      !window.confirm(
        `Replace “${label}” with your current scene? This can’t be undone.`,
      )
    ) {
      return;
    }
    setBusy(true);
    setErr("");
    try {
      await overrideSlot(selectedId);
      await refresh();
      flashNotice(`Updated “${label}”.`);
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function onDelete() {
    if (!selectedId) return;
    setBusy(true);
    try {
      await deleteSlot(selectedId);
      setSelectedId(null);
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  if (!open) return null;

  const hasSelection = selectedId !== null;

  return (
    <div class="fixed inset-0 z-100 flex items-center justify-center">
      <button
        type="button"
        aria-label="Close saves picker"
        onClick={close}
        class="absolute inset-0 bg-black/60 backdrop-blur-sm cursor-default"
      />
      <div class="relative w-[min(32rem,90vw)] max-h-[80vh] flex flex-col bg-neutral-900 border border-neutral-700 rounded-lg shadow-2xl text-neutral-100">
        <div class="flex items-center justify-between px-5 py-3 border-b border-neutral-800">
          <h2 class="text-lg font-semibold">Saved scenarios</h2>
          <button
            type="button"
            onClick={close}
            class="text-neutral-400 hover:text-neutral-100 text-xl leading-none cursor-pointer"
            aria-label="Close"
          >
            ×
          </button>
        </div>

        {/* CREATE — name input + save current */}
        <div class="px-5 py-3 border-b border-neutral-800 flex gap-2">
          <input
            type="text"
            value={saveName}
            onInput={(e) => setSaveName((e.target as HTMLInputElement).value)}
            placeholder="Name this save"
            class="flex-1 px-3 py-2 bg-neutral-950 border border-neutral-800 rounded text-sm"
            disabled={busy}
          />
          <button
            type="button"
            onClick={onCreate}
            disabled={busy || !saveName.trim()}
            class="px-4 py-2 bg-emerald-500 text-neutral-900 font-semibold rounded text-sm cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Save current
          </button>
        </div>
        {err ? <p class="text-red-400 text-sm px-5 py-2">{err}</p> : null}
        {notice ? (
          <p class="text-emerald-400 text-sm px-5 py-2">{notice}</p>
        ) : null}

        {/* READ — clickable rows */}
        <div class="overflow-y-auto flex-1 px-5 py-3">
          {slots.length === 0 ? (
            <p class="text-neutral-500 text-sm">No saves yet.</p>
          ) : (
            <ul class="space-y-2">
              {slots.map((s) => {
                const selected = s.id === selectedId;
                return (
                  <li key={s.id}>
                    <button
                      type="button"
                      onClick={() => toggleSelect(s.id)}
                      disabled={busy}
                      class={`w-full text-left flex items-center gap-3 px-3 py-2 bg-neutral-950 border rounded cursor-pointer transition-colors ${
                        selected
                          ? "border-sky-500 bg-sky-500/10"
                          : "border-neutral-800 hover:border-neutral-600 hover:bg-neutral-900"
                      } disabled:cursor-not-allowed disabled:opacity-60`}
                    >
                      <div class="flex-1 min-w-0">
                        <div class="font-medium text-sm truncate">
                          {s.name || "(unnamed)"}
                        </div>
                        <div class="text-xs text-neutral-500">
                          {new Date(s.updated_at).toLocaleString()}
                        </div>
                      </div>
                      {selected ? (
                        <span class="text-sky-400 text-xs">selected</span>
                      ) : null}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        {/* UPDATE / DELETE / READ — toolbar acts on selection */}
        <div class="px-5 py-3 border-t border-neutral-800 flex gap-2 justify-end">
          <button
            type="button"
            onClick={onDelete}
            disabled={busy || !hasSelection}
            class="px-3 py-2 bg-neutral-800 text-red-300 font-medium text-sm rounded cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Delete
          </button>
          <button
            type="button"
            onClick={onOverride}
            disabled={busy || !hasSelection}
            class="px-3 py-2 bg-amber-500 text-neutral-900 font-medium text-sm rounded cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Override
          </button>
          <button
            type="button"
            onClick={onLoad}
            disabled={busy || !hasSelection}
            class="px-3 py-2 bg-sky-500 text-neutral-900 font-semibold text-sm rounded cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Load
          </button>
        </div>
      </div>
    </div>
  );
}
