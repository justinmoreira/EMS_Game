import { useEffect, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import {
  createMatch,
  findByInvite,
  joinMatch,
  type Match,
  playUrl,
} from "@/lib/matches";
import { getProfiles, type Profile } from "@/lib/profile";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";

// Lobby browser: create a lobby (public or private), join an open public one,
// or jump straight in with an invite code / pasted id. Realtime keeps the open
// list live as lobbies appear, fill, and finish.
export default function MultiplayerLobby() {
  const user = authUser.value;
  const [matches, setMatches] = useState<Match[]>([]);
  const [names, setNames] = useState<Map<string, Profile>>(new Map());
  const [error, setError] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);

  // Create form.
  const [lobbyName, setLobbyName] = useState("");
  const [visibility, setVisibility] = useState<"public" | "private">("public");
  const [creating, setCreating] = useState(false);

  // Join-by-code.
  const [code, setCode] = useState("");
  const [joiningCode, setJoiningCode] = useState(false);

  // Initial fetch: open public lobbies + every lobby the user is already in.
  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("matches")
        .select("*")
        .or(
          `and(visibility.eq.public,status.in.(waiting,active)),host_id.eq.${user.id},guest_id.eq.${user.id}`,
        )
        .order("created_at", { ascending: false })
        .limit(60);
      if (!cancelled) setMatches((data as Match[]) ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  // Resolve host/guest display names for the rows we show.
  useEffect(() => {
    const ids = matches
      .flatMap((m) => [m.host_id, m.guest_id])
      .filter(Boolean) as string[];
    if (ids.length === 0) return;
    let cancelled = false;
    void getProfiles(ids).then((map) => {
      if (!cancelled) setNames(map);
    });
    return () => {
      cancelled = true;
    };
  }, [matches]);

  // Realtime: same anon-role race as MultiplayerMatch — wait for auth to settle
  // (realtime.setAuth) before subscribing or RLS silently drops broadcasts.
  useEffect(() => {
    if (authLoading.value || !user) return;
    const upsert = (row: Match) =>
      setMatches((prev) => {
        const next = prev.filter((m) => m.id !== row.id);
        // Keep open public lobbies and anything we're a participant in.
        const relevant =
          (row.visibility === "public" &&
            (row.status === "waiting" || row.status === "active")) ||
          row.host_id === user.id ||
          row.guest_id === user.id;
        return relevant ? [row, ...next] : next;
      });
    const channel = supabase
      .channel("mp-lobby-list")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "matches" },
        (p: { new: Match }) => upsert(p.new),
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "matches" },
        (p: { new: Match }) => upsert(p.new),
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "matches" },
        (p: { old: { id?: string } }) =>
          setMatches((prev) => prev.filter((m) => m.id !== p.old.id)),
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
      const m = await createMatch({
        name: lobbyName,
        visibility,
        hostId: user.id,
      });
      open(m.id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setCreating(false);
    }
  };

  const onJoinExisting = async (m: Match) => {
    if (!user) return;
    setBusyId(m.id);
    setError("");
    const res = await joinMatch(m.id);
    setBusyId(null);
    if (!res.ok) {
      setError(res.error ?? "Could not join.");
      return;
    }
    open(res.matchId ?? m.id);
  };

  const onJoinByCode = async () => {
    if (!user || !code.trim()) return;
    setJoiningCode(true);
    setError("");
    try {
      // findByInvite only sees lobbies we're allowed to read (public, or ones
      // we're already in). A private lobby we're not in returns null, so we fall
      // straight through to the RPC, which CAN reach it.
      const m = await findByInvite(code);
      if (m) {
        const mine = m.host_id === user.id || m.guest_id === user.id;
        if (mine) {
          open(m.id);
          return;
        }
        if (m.guest_id) {
          setError("That lobby is already full.");
          return;
        }
      }
      const res = await joinMatch(code);
      if (!res.ok || !res.matchId) {
        setError(res.error ?? "No open lobby for that code.");
        return;
      }
      open(res.matchId);
    } finally {
      setJoiningCode(false);
    }
  };

  const onDelete = async (id: string) => {
    setBusyId(id);
    setError("");
    const { error: e } = await supabase.from("matches").delete().eq("id", id);
    if (e) setError(e.message);
    setMatches((prev) => prev.filter((m) => m.id !== id));
    setBusyId(null);
  };

  if (authLoading.value) {
    return <Panel>Verifying session…</Panel>;
  }
  if (!user) {
    return (
      <Panel>Sign in (top right) to create or join a multiplayer match.</Panel>
    );
  }

  const nameOf = (id: string | null) =>
    id ? (names.get(id)?.display_name ?? "Player") : "—";

  const yourMatches = matches.filter(
    (m) => m.host_id === user.id || m.guest_id === user.id,
  );
  const openMatches = matches.filter(
    (m) =>
      m.visibility === "public" &&
      (m.status === "waiting" || m.status === "active") &&
      m.host_id !== user.id &&
      m.guest_id !== user.id,
  );

  return (
    <div class="flex flex-col gap-6">
      {/* Create + join-by-code */}
      <div class="grid gap-4 md:grid-cols-2">
        <div class="rounded-xl border border-white/10 bg-black/45 p-5 backdrop-blur-md">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-neutral-400">
            Create a lobby
          </h2>
          <input
            type="text"
            value={lobbyName}
            maxLength={40}
            onInput={(e) => setLobbyName((e.target as HTMLInputElement).value)}
            placeholder="Lobby name"
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
              ? "Listed below for anyone to join — first come, first served."
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
            Paste an invite code (or lobby id) a friend shared with you.
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

      {yourMatches.length > 0 && (
        <LobbyTable
          title="Your lobbies"
          rows={yourMatches}
          user={user}
          nameOf={nameOf}
          busyId={busyId}
          onOpen={open}
          onJoin={onJoinExisting}
          onDelete={onDelete}
        />
      )}

      <LobbyTable
        title="Open public lobbies"
        rows={openMatches}
        user={user}
        nameOf={nameOf}
        busyId={busyId}
        onOpen={open}
        onJoin={onJoinExisting}
        onDelete={onDelete}
        emptyHint="No open lobbies right now — create one above."
      />
    </div>
  );
}

function LobbyTable({
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
  rows: Match[];
  user: { id: string };
  nameOf: (id: string | null) => string;
  busyId: string | null;
  onOpen: (id: string) => void;
  onJoin: (m: Match) => void;
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
              <th class="px-6 py-2 text-left font-medium">Lobby</th>
              <th class="px-6 py-2 text-left font-medium">Host</th>
              <th class="px-6 py-2 text-left font-medium">Players</th>
              <th class="px-6 py-2 text-left font-medium">Status</th>
              <th class="px-6 py-2 text-right font-medium" />
            </tr>
          </thead>
          <tbody class="divide-y divide-white/5">
            {rows.map((m) => {
              const isHost = m.host_id === user.id;
              const isGuest = m.guest_id === user.id;
              const joined = isHost || isGuest;
              const full = !!m.host_id && !!m.guest_id && !joined;
              const count = (m.host_id ? 1 : 0) + (m.guest_id ? 1 : 0);
              const busy = busyId === m.id;
              return (
                <tr key={m.id} class="hover:bg-white/5">
                  <td class="px-6 py-3">
                    <div class="font-medium text-white">{m.name}</div>
                    <div class="font-mono text-xs text-neutral-500">
                      {m.id}
                      {m.visibility === "private" && (
                        <span class="ml-2 rounded bg-neutral-700/50 px-1.5 py-0.5 text-[10px] uppercase text-neutral-300">
                          private
                        </span>
                      )}
                    </div>
                  </td>
                  <td class="px-6 py-3 text-neutral-300">
                    {nameOf(m.host_id)}
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
                    <StatusBadge status={m.status} />
                  </td>
                  <td class="px-6 py-3 text-right">
                    <div class="flex items-center justify-end gap-2">
                      {joined ? (
                        <Btn onClick={() => onOpen(m.id)}>Open</Btn>
                      ) : full || m.status === "finished" ? (
                        <span class="rounded-lg bg-neutral-800 px-3 py-1.5 text-xs font-semibold text-neutral-500">
                          {m.status === "finished" ? "Ended" : "Full"}
                        </span>
                      ) : (
                        <Btn onClick={() => onJoin(m)} disabled={busy}>
                          {busy ? "…" : "Join"}
                        </Btn>
                      )}
                      {isHost && (
                        <button
                          type="button"
                          onClick={() => onDelete(m.id)}
                          title="Delete lobby"
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
        : status === "finished"
          ? "bg-sky-500/15 text-sky-300"
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
