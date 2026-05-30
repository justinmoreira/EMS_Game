import { useEffect, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";
import type { Tables } from "./../lib/database.types";

// PoC: one hard-coded lobby ID. The table can already render N rows —
// once we support multi-lobby, just drop the filter and let `matches`
// rows come through.
const POC_LOBBY_ID = "poc-lobby";

type MatchRow = Tables<"matches">;

export default function MultiplayerLobby() {
  const user = authUser.value;
  const [matches, setMatches] = useState<MatchRow[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState("");

  // Fetch existing lobbies. NOTE: no auto-claim — that only happens
  // when the user explicitly clicks "Join".
  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("matches")
        .select("*")
        .order("created_at", { ascending: false });
      if (!cancelled) setMatches((data as MatchRow[]) ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  // Realtime: split into INSERT/UPDATE/DELETE listeners — the wildcard
  // 'event: "*"' overload doesn't resolve cleanly against the typed
  // supabase client, and the per-event handlers are clearer anyway.
  useEffect(() => {
    // Same anon-role race as MultiplayerMatch: subscribing before
    // realtime.setAuth(token) has been called (which lib/auth.ts only does
    // inside the getSession resolve) pins the channel to `anon` and RLS
    // silently drops all broadcasts. Wait for authLoading to flip false.
    if (authLoading.value || !user) return;
    const channel = supabase
      .channel("mp-lobby-list")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "matches" },
        (payload: { new: MatchRow }) =>
          setMatches((prev) => [
            payload.new,
            ...prev.filter((m) => m.id !== payload.new.id),
          ]),
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "matches" },
        (payload: { new: MatchRow }) =>
          setMatches((prev) =>
            prev.map((m) => (m.id === payload.new.id ? payload.new : m)),
          ),
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "matches" },
        (payload: { old: { id?: string } }) =>
          setMatches((prev) =>
            prev.filter((m) => m.id !== payload.old.id),
          ),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [user?.id, authLoading.value]);

  const joinOrCreate = async (matchId: string, existing: MatchRow | null) => {
    if (!user) return;
    setBusyId(matchId);
    setError("");

    if (!existing) {
      // Hard-coded lobby placeholder hasn't been created in DB yet —
      // first joiner creates it as host.
      const seed = Math.floor(Math.random() * 0x7fffffff);
      const ins = await supabase
        .from("matches")
        .insert({ id: matchId, seed, host_id: user.id, status: "waiting" })
        .select()
        .maybeSingle();
      if (ins.error) {
        // Lost the create race — fall through to guest-claim path below
        // by refetching.
        const re = await supabase
          .from("matches")
          .select("*")
          .eq("id", matchId)
          .maybeSingle();
        if (re.data && !re.data.guest_id && re.data.host_id !== user.id) {
          await supabase
            .from("matches")
            .update({ guest_id: user.id })
            .eq("id", matchId)
            .is("guest_id", null);
        }
      }
    } else if (!existing.guest_id && existing.host_id !== user.id) {
      const upd = await supabase
        .from("matches")
        .update({ guest_id: user.id })
        .eq("id", matchId)
        .is("guest_id", null)
        .select()
        .maybeSingle();
      if (upd.error) setError(upd.error.message);
    }

    setBusyId(null);
  };

  const openMatch = (matchId: string) => {
    window.location.href = `${BASE_URL}/multiplayer/play?id=${encodeURIComponent(matchId)}`;
  };

  const resetMatch = async (matchId: string) => {
    setBusyId(matchId);
    setError("");
    const { error: e } = await supabase
      .from("matches")
      .delete()
      .eq("id", matchId);
    if (e) setError(e.message);
    setBusyId(null);
  };

  // Always render the PoC row, backed by DB state if it exists.
  const pocRow = matches.find((m) => m.id === POC_LOBBY_ID) ?? null;
  const rows: { id: string; match: MatchRow | null }[] = [
    { id: POC_LOBBY_ID, match: pocRow },
    ...matches
      .filter((m) => m.id !== POC_LOBBY_ID)
      .map((m) => ({ id: m.id, match: m })),
  ];

  if (authLoading.value) {
    return (
      <div class="rounded-xl border border-white/10 bg-black/45 p-6 backdrop-blur-md">
        <p class="text-neutral-300">Verifying session...</p>
      </div>
    );
  }

  if (!user) {
    return (
      <div class="rounded-xl border border-white/10 bg-black/45 p-6 backdrop-blur-md">
        <p class="text-neutral-300">
          Sign in (top right) to join the multiplayer PoC.
        </p>
      </div>
    );
  }

  return (
    <div class="flex flex-col gap-4">
      <div class="overflow-hidden rounded-xl border border-white/10 bg-black/45 backdrop-blur-md">
        <header class="border-b border-white/10 px-6 py-4">
          <h2 class="text-lg font-bold text-white">Lobbies</h2>
          <p class="mt-1 text-xs text-neutral-400">
            Click Join to claim a seat. Once registered, Open the lobby to load
            the match.
          </p>
        </header>
        <table class="w-full text-sm">
          <thead class="bg-white/5 text-xs uppercase tracking-wide text-neutral-400">
            <tr>
              <th class="px-6 py-2 text-left font-medium">Lobby</th>
              <th class="px-6 py-2 text-left font-medium">Seed</th>
              <th class="px-6 py-2 text-left font-medium">Players</th>
              <th class="px-6 py-2 text-left font-medium">Status</th>
              <th class="px-6 py-2 text-right font-medium" />
            </tr>
          </thead>
          <tbody class="divide-y divide-white/5">
            {rows.map(({ id, match }) => {
              const isHost = match?.host_id === user.id;
              const isGuest = match?.guest_id === user.id;
              const isJoined = isHost || isGuest;
              const isFull =
                !!match && !!match.host_id && !!match.guest_id && !isJoined;
              const playerCount =
                (match?.host_id ? 1 : 0) + (match?.guest_id ? 1 : 0);
              const role = isHost ? "Host" : isGuest ? "Guest" : "—";
              const status = match?.status ?? "open";
              const busy = busyId === id;

              return (
                <tr key={id} class="hover:bg-white/2">
                  <td class="px-6 py-3 font-mono text-white">{id}</td>
                  <td class="px-6 py-3 font-mono text-emerald-400">
                    {match ? match.seed : "—"}
                  </td>
                  <td class="px-6 py-3 text-neutral-300">
                    {playerCount}/2{" "}
                    {isJoined && (
                      <span class="ml-2 text-xs text-emerald-400">
                        (you: {role})
                      </span>
                    )}
                  </td>
                  <td class="px-6 py-3">
                    <span
                      class={`inline-flex items-center gap-2 rounded-full px-2 py-0.5 text-xs font-medium ${
                        status === "active"
                          ? "bg-emerald-500/15 text-emerald-300"
                          : status === "waiting"
                            ? "bg-yellow-500/15 text-yellow-300"
                            : "bg-neutral-500/15 text-neutral-300"
                      }`}
                    >
                      {status}
                    </span>
                  </td>
                  <td class="px-6 py-3 text-right">
                    <div class="flex items-center justify-end gap-2">
                      {isJoined ? (
                        <button
                          type="button"
                          onClick={() => openMatch(id)}
                          class="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-semibold text-black hover:bg-emerald-400"
                        >
                          Open
                        </button>
                      ) : isFull ? (
                        <button
                          type="button"
                          disabled
                          class="rounded-lg bg-neutral-800 px-3 py-1.5 text-xs font-semibold text-neutral-500"
                        >
                          Full
                        </button>
                      ) : (
                        <button
                          type="button"
                          onClick={() => joinOrCreate(id, match)}
                          disabled={busy}
                          class="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-semibold text-black hover:bg-emerald-400 disabled:opacity-50"
                        >
                          {busy ? "..." : "Join"}
                        </button>
                      )}
                      {match && (
                        <button
                          type="button"
                          onClick={() => resetMatch(id)}
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
      </div>
      {error && <p class="text-sm text-red-400">{error}</p>}
    </div>
  );
}
