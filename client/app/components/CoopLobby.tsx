import { useEffect, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import {
  type CollabRoom,
  createRoom,
  deleteRoom,
  findByInvite,
  joinRoom,
  playUrl,
} from "@/lib/collab";
import { getProfiles, type Profile } from "@/lib/profile";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";

// Co-op lobby browser: create a shared sandbox room (public or private), join an
// open public one, or jump in with an invite code / pasted id. Realtime keeps
// the open list live as rooms appear and fill. Mirrors MultiplayerLobby, minus
// the competitive framing (no "finished" state — a room stays joinable while it
// has an empty seat).
export default function CoopLobby() {
  const user = authUser.value;
  const [rooms, setRooms] = useState<CollabRoom[]>([]);
  const [names, setNames] = useState<Map<string, Profile>>(new Map());
  const [error, setError] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);

  // Create form.
  const [roomName, setRoomName] = useState("");
  const [visibility, setVisibility] = useState<"public" | "private">("public");
  const [creating, setCreating] = useState(false);

  // Join-by-code.
  const [code, setCode] = useState("");
  const [joiningCode, setJoiningCode] = useState(false);

  // Initial fetch: open public rooms + every room the user is already in.
  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("collab_rooms")
        .select("*")
        .or(
          `and(visibility.eq.public,status.in.(waiting,active)),host_id.eq.${user.id},guest_id.eq.${user.id}`,
        )
        .order("created_at", { ascending: false })
        .limit(60);
      if (!cancelled) setRooms((data as CollabRoom[]) ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  // Resolve host/guest display names for the rows we show.
  useEffect(() => {
    const ids = rooms
      .flatMap((r) => [r.host_id, r.guest_id])
      .filter(Boolean) as string[];
    if (ids.length === 0) return;
    let cancelled = false;
    void getProfiles(ids).then((map) => {
      if (!cancelled) setNames(map);
    });
    return () => {
      cancelled = true;
    };
  }, [rooms]);

  // Realtime: wait for auth to settle (realtime.setAuth) before subscribing or
  // RLS silently drops broadcasts — same anon-role race as multiplayer.
  useEffect(() => {
    if (authLoading.value || !user) return;
    const upsert = (row: CollabRoom) =>
      setRooms((prev) => {
        const next = prev.filter((r) => r.id !== row.id);
        const relevant =
          (row.visibility === "public" &&
            (row.status === "waiting" || row.status === "active")) ||
          row.host_id === user.id ||
          row.guest_id === user.id;
        return relevant ? [row, ...next] : next;
      });
    const channel = supabase
      .channel("coop-lobby-list")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "collab_rooms" },
        (p: { new: CollabRoom }) => upsert(p.new),
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "collab_rooms" },
        (p: { new: CollabRoom }) => upsert(p.new),
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "collab_rooms" },
        (p: { old: { id?: string } }) =>
          setRooms((prev) => prev.filter((r) => r.id !== p.old.id)),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [user?.id, authLoading.value]);

  const open = (id: string) => {
    window.location.href = playUrl(BASE_URL, id);
  };

  const onCreate = async () => {
    if (!user) return;
    setCreating(true);
    setError("");
    try {
      const r = await createRoom({
        name: roomName,
        visibility,
        hostId: user.id,
      });
      open(r.id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setCreating(false);
    }
  };

  const onJoinExisting = async (r: CollabRoom) => {
    if (!user) return;
    setBusyId(r.id);
    setError("");
    const res = await joinRoom(r.id);
    setBusyId(null);
    if (!res.ok) {
      setError(res.error ?? "Could not join.");
      return;
    }
    open(res.roomId ?? r.id);
  };

  const onJoinByCode = async () => {
    if (!user || !code.trim()) return;
    setJoiningCode(true);
    setError("");
    try {
      // findByInvite only sees rooms we're allowed to read (public, or ones
      // we're already in). A private room we're not in returns null, so we fall
      // through to the RPC, which CAN reach it.
      const r = await findByInvite(code);
      if (r) {
        const mine = r.host_id === user.id || r.guest_id === user.id;
        if (mine) {
          open(r.id);
          return;
        }
        if (r.guest_id) {
          setError("That room is already full.");
          return;
        }
      }
      const res = await joinRoom(code);
      if (!res.ok || !res.roomId) {
        setError(res.error ?? "No open room for that code.");
        return;
      }
      open(res.roomId);
    } finally {
      setJoiningCode(false);
    }
  };

  const onDelete = async (id: string) => {
    setBusyId(id);
    setError("");
    try {
      await deleteRoom(id);
      setRooms((prev) => prev.filter((r) => r.id !== id));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusyId(null);
    }
  };

  if (authLoading.value) {
    return <Panel>Verifying session…</Panel>;
  }
  if (!user) {
    return (
      <Panel>Sign in (top right) to create or join a co-op sandbox.</Panel>
    );
  }

  const nameOf = (id: string | null) =>
    id ? (names.get(id)?.display_name ?? "Player") : "—";

  const yourRooms = rooms.filter(
    (r) => r.host_id === user.id || r.guest_id === user.id,
  );
  const openRooms = rooms.filter(
    (r) =>
      r.visibility === "public" &&
      (r.status === "waiting" || r.status === "active") &&
      r.host_id !== user.id &&
      r.guest_id !== user.id,
  );

  return (
    <div class="flex flex-col gap-6">
      {/* Create + join-by-code */}
      <div class="grid gap-4 md:grid-cols-2">
        <div class="rounded-xl border border-white/10 bg-black/45 p-5 backdrop-blur-md">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-neutral-400">
            Create a room
          </h2>
          <input
            type="text"
            value={roomName}
            maxLength={40}
            onInput={(e) => setRoomName((e.target as HTMLInputElement).value)}
            placeholder="Room name"
            class="mt-3 w-full rounded-lg border border-neutral-800 bg-neutral-950 px-3 py-2 text-sm text-white placeholder-neutral-500 focus:border-emerald-500 focus:outline-none"
          />
          <div class="mt-3 flex gap-2">
            {(["public", "private"] as const).map((v) => (
              <button
                key={v}
                type="button"
                onClick={() => setVisibility(v)}
                class={`flex-1 rounded-lg border px-3 py-1.5 text-xs font-semibold capitalize transition-colors ${
                  visibility === v
                    ? "border-emerald-500 bg-emerald-500/10 text-emerald-300"
                    : "border-neutral-800 text-neutral-400 hover:border-neutral-600"
                }`}
              >
                {v}
              </button>
            ))}
          </div>
          <p class="mt-2 text-xs text-neutral-500">
            {visibility === "public"
              ? "Listed below for anyone to hop in and build with you."
              : "Hidden from the list. Share the invite code or link to let someone in."}
          </p>
          <button
            type="button"
            onClick={onCreate}
            disabled={creating}
            class="mt-3 w-full rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-black hover:bg-emerald-400 disabled:opacity-50"
          >
            {creating ? "Creating…" : "Create & open"}
          </button>
        </div>

        <div class="rounded-xl border border-white/10 bg-black/45 p-5 backdrop-blur-md">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-neutral-400">
            Join by code
          </h2>
          <p class="mt-2 text-xs text-neutral-500">
            Paste an invite code (or room id) a friend shared with you.
          </p>
          <div class="mt-3 flex gap-2">
            <input
              type="text"
              value={code}
              onInput={(e) =>
                setCode((e.target as HTMLInputElement).value.toUpperCase())
              }
              onKeyDown={(e) => {
                if (e.key === "Enter") void onJoinByCode();
              }}
              placeholder="e.g. K7P2QX"
              class="flex-1 rounded-lg border border-neutral-800 bg-neutral-950 px-3 py-2 font-mono text-sm uppercase tracking-widest text-white placeholder-neutral-600 focus:border-emerald-500 focus:outline-none"
            />
            <button
              type="button"
              onClick={onJoinByCode}
              disabled={joiningCode || !code.trim()}
              class="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-black hover:bg-emerald-400 disabled:opacity-50"
            >
              {joiningCode ? "…" : "Join"}
            </button>
          </div>
        </div>
      </div>

      {error && <p class="text-sm text-red-400">{error}</p>}

      {yourRooms.length > 0 && (
        <RoomTable
          title="Your rooms"
          rows={yourRooms}
          user={user}
          nameOf={nameOf}
          busyId={busyId}
          onOpen={open}
          onJoin={onJoinExisting}
          onDelete={onDelete}
        />
      )}

      <RoomTable
        title="Open public rooms"
        rows={openRooms}
        user={user}
        nameOf={nameOf}
        busyId={busyId}
        onOpen={open}
        onJoin={onJoinExisting}
        onDelete={onDelete}
        emptyHint="No open rooms right now — create one above."
      />
    </div>
  );
}

function RoomTable({
  title,
  rows,
  user,
  nameOf,
  busyId,
  onOpen,
  onJoin,
  onDelete,
  emptyHint,
}: {
  title: string;
  rows: CollabRoom[];
  user: { id: string };
  nameOf: (id: string | null) => string;
  busyId: string | null;
  onOpen: (id: string) => void;
  onJoin: (r: CollabRoom) => void;
  onDelete: (id: string) => void;
  emptyHint?: string;
}) {
  return (
    <div class="overflow-hidden rounded-xl border border-white/10 bg-black/45 backdrop-blur-md">
      <header class="border-b border-white/10 px-6 py-3">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-neutral-300">
          {title}
        </h2>
      </header>
      {rows.length === 0 ? (
        <p class="px-6 py-5 text-sm text-neutral-500">
          {emptyHint ?? "Nothing here yet."}
        </p>
      ) : (
        <table class="w-full text-sm">
          <thead class="bg-white/5 text-xs uppercase tracking-wide text-neutral-400">
            <tr>
              <th class="px-6 py-2 text-left font-medium">Room</th>
              <th class="px-6 py-2 text-left font-medium">Host</th>
              <th class="px-6 py-2 text-left font-medium">Players</th>
              <th class="px-6 py-2 text-left font-medium">Status</th>
              <th class="px-6 py-2 text-right font-medium" />
            </tr>
          </thead>
          <tbody class="divide-y divide-white/5">
            {rows.map((r) => {
              const isHost = r.host_id === user.id;
              const isGuest = r.guest_id === user.id;
              const joined = isHost || isGuest;
              const full = !!r.host_id && !!r.guest_id && !joined;
              const count = (r.host_id ? 1 : 0) + (r.guest_id ? 1 : 0);
              const busy = busyId === r.id;
              return (
                <tr key={r.id} class="hover:bg-white/5">
                  <td class="px-6 py-3">
                    <div class="font-medium text-white">{r.name}</div>
                    <div class="font-mono text-xs text-neutral-500">
                      {r.id}
                      {r.visibility === "private" && (
                        <span class="ml-2 rounded bg-neutral-700/50 px-1.5 py-0.5 text-[10px] uppercase text-neutral-300">
                          private
                        </span>
                      )}
                    </div>
                  </td>
                  <td class="px-6 py-3 text-neutral-300">
                    {nameOf(r.host_id)}
                  </td>
                  <td class="px-6 py-3 text-neutral-300">
                    {count}/2
                    {joined && (
                      <span class="ml-2 text-xs text-emerald-400">
                        (you: {isHost ? "Host" : "Guest"})
                      </span>
                    )}
                  </td>
                  <td class="px-6 py-3">
                    <StatusBadge status={r.status} />
                  </td>
                  <td class="px-6 py-3 text-right">
                    <div class="flex items-center justify-end gap-2">
                      {joined ? (
                        <Btn onClick={() => onOpen(r.id)}>Open</Btn>
                      ) : full ? (
                        <span class="rounded-lg bg-neutral-800 px-3 py-1.5 text-xs font-semibold text-neutral-500">
                          Full
                        </span>
                      ) : (
                        <Btn onClick={() => onJoin(r)} disabled={busy}>
                          {busy ? "…" : "Join"}
                        </Btn>
                      )}
                      {isHost && (
                        <button
                          type="button"
                          onClick={() => onDelete(r.id)}
                          title="Delete room"
                          class="rounded-lg border border-neutral-700 px-2 py-1.5 text-xs text-neutral-400 hover:border-red-400 hover:text-red-400"
                        >
                          ×
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}

function Btn({
  children,
  onClick,
  disabled,
}: {
  children: preact.ComponentChildren;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      class="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-semibold text-black hover:bg-emerald-400 disabled:opacity-50"
    >
      {children}
    </button>
  );
}

function StatusBadge({ status }: { status: string }) {
  const cls =
    status === "active"
      ? "bg-emerald-500/15 text-emerald-300"
      : status === "waiting"
        ? "bg-yellow-500/15 text-yellow-300"
        : "bg-neutral-500/15 text-neutral-300";
  return (
    <span
      class={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${cls}`}
    >
      {status}
    </span>
  );
}

function Panel({ children }: { children: preact.ComponentChildren }) {
  return (
    <div class="rounded-xl border border-white/10 bg-black/45 p-6 backdrop-blur-md">
      <p class="text-neutral-300">{children}</p>
    </div>
  );
}
