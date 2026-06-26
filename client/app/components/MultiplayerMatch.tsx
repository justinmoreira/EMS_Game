import { useEffect, useRef, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import { createMatch } from "@/lib/matches";
import { getProfiles, type Profile } from "@/lib/profile";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";
import type { Json, Tables } from "./../lib/database.types";

type MatchRow = Tables<"matches">;
type ActionRow = Tables<"match_actions">;

declare global {
  interface Window {
    MULTIPLAYER_MATCH?: MatchRow;
    MULTIPLAYER_PLAYER_ID?: string;
    submitMpAction?: (boardJson?: string) => Promise<void>;
    godotApplyOpponentBoard?: (boardJson: string, ownerId: string) => void;
    godotOnTurnAdvance?: (turn: number) => void;
    mpReportWinner?: (winnerId: string) => void;
  }
}

function publishMatchToWindow(match: MatchRow | null) {
  if (typeof window === "undefined") return;
  if (match) window.MULTIPLAYER_MATCH = match;
  else delete window.MULTIPLAYER_MATCH;
}

function publishPlayerIdToWindow(id: string | null) {
  if (typeof window === "undefined") return;
  if (id) window.MULTIPLAYER_PLAYER_ID = id;
  else delete window.MULTIPLAYER_PLAYER_ID;
}

function getMatchIdFromUrl(): string | null {
  if (typeof window === "undefined") return null;
  return new URLSearchParams(window.location.search).get("id");
}

export default function MultiplayerMatch() {
  const user = authUser.value;
  const verifying = authLoading.value;
  const [matchId] = useState<string | null>(getMatchIdFromUrl);
  const [match, setMatch] = useState<MatchRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [pendingOpponentAction, setPendingOpponentAction] =
    useState<ActionRow | null>(null);
  // True once we've submitted for the current turn, so the HUD can show
  // "waiting for opponent". Cleared when the turn advances.
  const [submittedTurn, setSubmittedTurn] = useState<number | null>(null);
  const [profiles, setProfiles] = useState<Map<string, Profile>>(new Map());
  const reportedWinner = useRef(false);

  // Auth gate (see original notes): only redirect once verification resolves.
  useEffect(() => {
    if (verifying) return;
    if (user === null) {
      window.location.href = `${BASE_URL}/singleplayer`;
    }
  }, [verifying, user]);

  // Initial match fetch.
  useEffect(() => {
    if (!matchId) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("matches")
        .select("*")
        .eq("id", matchId)
        .maybeSingle();
      if (!cancelled) {
        setMatch(data);
        publishMatchToWindow(data);
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [matchId]);

  // Resolve both players' display names for the HUD/overlays.
  useEffect(() => {
    const ids = [match?.host_id, match?.guest_id].filter(Boolean) as string[];
    if (ids.length === 0) return;
    let cancelled = false;
    void getProfiles(ids).then((m) => {
      if (!cancelled) setProfiles(m);
    });
    return () => {
      cancelled = true;
    };
  }, [match?.host_id, match?.guest_id]);

  useEffect(() => {
    return () => {
      publishMatchToWindow(null);
      publishPlayerIdToWindow(null);
    };
  }, []);

  useEffect(() => {
    publishPlayerIdToWindow(user?.id ?? null);
  }, [user?.id]);

  // Wire the Godot SUBMIT button → DB write for the current turn.
  useEffect(() => {
    if (!user || !match) return;
    const turnAtBind = match.current_turn;
    window.submitMpAction = async (boardJson?: string) => {
      let board: Json = null;
      if (boardJson) {
        try {
          board = JSON.parse(boardJson) as Json;
        } catch (e) {
          console.warn("[mp/submit] board JSON parse failed:", e);
        }
      }
      const { error } = await supabase.from("match_actions").insert({
        match_id: match.id,
        turn_number: match.current_turn,
        player_id: user.id,
        action: {
          type: board ? "snapshot" : "noop",
          board,
          submitted_at: new Date().toISOString(),
        },
      });
      if (error) {
        console.error("[mp/submit] insert FAILED:", error.message);
      } else {
        setSubmittedTurn(turnAtBind);
      }
    };
    return () => {
      delete window.submitMpAction;
    };
  }, [user, match]);

  // Register the win reporter Godot calls when it detects the end of the
  // match. finish_match is idempotent, so both clients reporting is fine.
  useEffect(() => {
    if (!matchId) return;
    window.mpReportWinner = (winnerId: string) => {
      if (reportedWinner.current) return;
      reportedWinner.current = true;
      void supabase
        .rpc("finish_match", {
          p_match_id: matchId,
          // Empty winnerId ⇒ a draw, which the function takes as a null uuid.
          // The generated arg type narrows to string, so cast the null through.
          p_winner_id: (winnerId || null) as string,
        })
        .then(({ error }) => {
          if (error) {
            console.error("[mp] finish_match failed:", error.message);
            reportedWinner.current = false;
          }
        });
    };
    return () => {
      delete window.mpReportWinner;
    };
  }, [matchId]);

  // Realtime: opponent actions (buffered for WEGO) + match updates.
  useEffect(() => {
    if (!matchId || verifying || !user) return;

    const handleOpponentInsert = (payload: { new: ActionRow }) => {
      const a = payload.new;
      if (a.match_id !== matchId) return;
      if (a.player_id === user.id) return;
      setPendingOpponentAction(a);
    };

    const handleMatchUpdate = (payload: { new: MatchRow }) => {
      const row = payload.new;
      if (row.id !== matchId) return;
      setMatch(row);
      publishMatchToWindow(row);
      // Tell Godot the shared turn ticked (resets the per-turn placement cap).
      if (typeof window.godotOnTurnAdvance === "function") {
        window.godotOnTurnAdvance(row.current_turn);
      }
      // Turn-limit draw: nobody achieved the sole connection in time.
      if (
        row.status !== "finished" &&
        row.current_turn >= row.max_turns &&
        typeof window.mpReportWinner === "function" &&
        !reportedWinner.current
      ) {
        window.mpReportWinner("");
      }
    };

    const channel = supabase
      .channel(`mp-match-${matchId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "matches" },
        handleMatchUpdate,
      )
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "match_actions" },
        handleOpponentInsert,
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [matchId, user?.id, verifying]);

  // Clear the local "submitted" flag once the turn actually advances.
  useEffect(() => {
    if (match && submittedTurn !== null && match.current_turn > submittedTurn) {
      setSubmittedTurn(null);
    }
  }, [match?.current_turn, submittedTurn]);

  // WEGO commit: apply the buffered opponent board only after the turn advances.
  useEffect(() => {
    if (!match || !pendingOpponentAction) return;
    if (match.current_turn <= pendingOpponentAction.turn_number) return;

    const action = pendingOpponentAction.action as { board?: Json } | null;
    if (!action || action.board == null) {
      setPendingOpponentAction(null);
      return;
    }
    const fn = window.godotApplyOpponentBoard;
    if (typeof fn !== "function") return;
    fn(JSON.stringify(action.board), pendingOpponentAction.player_id);
    setPendingOpponentAction(null);
  }, [match?.current_turn, pendingOpponentAction]);

  // Replay-on-load: rebuild both boards from the DB (own always; opponent only
  // for already-committed turns, preserving no-peek).
  useEffect(() => {
    if (!matchId || !user) return;
    const myId = user.id;
    let cancelled = false;
    let pollTimer: ReturnType<typeof setInterval> | null = null;

    (async () => {
      const { data: m } = await supabase
        .from("matches")
        .select("current_turn")
        .eq("id", matchId)
        .maybeSingle();
      const currentTurn = m?.current_turn ?? 0;

      const { data, error } = await supabase
        .from("match_actions")
        .select("*")
        .eq("match_id", matchId)
        .order("turn_number", { ascending: true });
      if (cancelled || error || !data) return;

      const latest = new Map<string, ActionRow>();
      for (const a of data) {
        if (a.player_id !== myId && a.turn_number >= currentTurn) continue;
        latest.set(a.player_id, a);
      }
      if (latest.size === 0) return;

      const applyAll = (): boolean => {
        const fn = window.godotApplyOpponentBoard;
        if (typeof fn !== "function") return false;
        for (const a of latest.values()) {
          const board = (a.action as { board?: Json } | null)?.board;
          if (board != null) fn(JSON.stringify(board), a.player_id);
        }
        return true;
      };

      if (!applyAll()) {
        pollTimer = setInterval(() => {
          if (cancelled || applyAll()) {
            if (pollTimer) clearInterval(pollTimer);
            pollTimer = null;
          }
        }, 200);
      }
    })();

    return () => {
      cancelled = true;
      if (pollTimer) clearInterval(pollTimer);
    };
  }, [matchId, user?.id]);

  // ── Render ──────────────────────────────────────────────────────────────

  if (verifying) {
    return (
      <Overlay>
        <Card title="Verifying session…">
          <p class="text-sm text-neutral-400">Checking your authentication.</p>
        </Card>
      </Overlay>
    );
  }
  if (user === null) {
    return (
      <Overlay>
        <Card title="Signed out">
          <p class="text-sm text-neutral-400">Returning to singleplayer…</p>
        </Card>
      </Overlay>
    );
  }
  if (!matchId) {
    return (
      <Overlay>
        <Card title="No match selected">
          <p class="text-sm text-neutral-400">
            Open this page from the lobby list.
          </p>
          <BackToLobbiesButton />
        </Card>
      </Overlay>
    );
  }
  if (loading) {
    return (
      <Overlay>
        <Card title="Loading match…">
          <p class="text-sm text-neutral-400">Fetching lobby state.</p>
        </Card>
      </Overlay>
    );
  }
  if (!match) {
    return (
      <Overlay>
        <Card title="Match not found">
          <p class="text-sm text-neutral-400">
            Lobby <span class="font-mono text-white">{matchId}</span> doesn't
            exist.
          </p>
          <BackToLobbiesButton />
        </Card>
      </Overlay>
    );
  }

  const isHost = user.id === match.host_id;
  const isGuest = user.id === match.guest_id;
  const role = isHost ? "Host (P1)" : isGuest ? "Guest (P2)" : "Spectator";
  const oppId = isHost ? match.guest_id : match.host_id;
  const myName = profiles.get(user.id)?.display_name ?? "You";
  const oppName = oppId
    ? (profiles.get(oppId)?.display_name ?? "Opponent")
    : null;

  // Finished → result modal.
  if (match.status === "finished") {
    const draw = !match.winner_id;
    const won = match.winner_id === user.id;
    return (
      <Overlay>
        <Card title={draw ? "Draw" : won ? "Victory" : "Defeat"}>
          <div
            class={`text-3xl font-black ${
              draw
                ? "text-neutral-300"
                : won
                  ? "text-emerald-400"
                  : "text-red-400"
            }`}
          >
            {draw ? "Stalemate" : won ? "You won!" : "You lost"}
          </div>
          <p class="text-sm text-neutral-400">
            {draw
              ? "The turn limit was reached with no sole connection."
              : won
                ? "You held the only source → target connection."
                : `${oppName ?? "Your opponent"} held the only connection.`}
          </p>
          <RematchButtons hostId={user.id} name={match.name} />
        </Card>
      </Overlay>
    );
  }

  // Active → non-blocking HUD over the canvas.
  if (match.status === "active") {
    const waiting = submittedTurn === match.current_turn;
    return (
      <MatchHud
        name={match.name}
        turn={match.current_turn}
        maxTurns={match.max_turns}
        role={role}
        myName={myName}
        oppName={oppName}
        waiting={waiting}
      />
    );
  }

  // Waiting for a second player.
  const inviteCode = match.invite_code ?? match.id;
  const shareUrl =
    typeof window !== "undefined"
      ? `${window.location.origin}${BASE_URL}/multiplayer/play?id=${encodeURIComponent(match.id)}`
      : "";
  return (
    <Overlay>
      <Card title="Waiting for a second player…">
        <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
          <dt class="text-neutral-500">Lobby</dt>
          <dd class="text-white">{match.name}</dd>
          <dt class="text-neutral-500">You</dt>
          <dd class="text-white">
            {myName} — {role}
          </dd>
          <dt class="text-neutral-500">Visibility</dt>
          <dd class="text-white capitalize">{match.visibility}</dd>
        </dl>
        <CopyField label="Invite code" value={inviteCode} mono />
        <CopyField label="Invite link" value={shareUrl} />
        <div class="flex items-center gap-2 text-xs text-neutral-400">
          <span class="inline-block h-2 w-2 animate-pulse rounded-full bg-yellow-500" />
          Share either with the other player to fill the guest seat.
        </div>
        <BackToLobbiesButton />
      </Card>
    </Overlay>
  );
}

// ── In-match HUD (non-blocking) ──────────────────────────────────────────
function MatchHud({
  name,
  turn,
  maxTurns,
  role,
  myName,
  oppName,
  waiting,
}: {
  name: string;
  turn: number;
  maxTurns: number;
  role: string;
  myName: string;
  oppName: string | null;
  waiting: boolean;
}) {
  return (
    <div class="pointer-events-none fixed left-1/2 top-16 z-30 -translate-x-1/2">
      <div class="flex items-center gap-4 rounded-xl border border-white/10 bg-black/70 px-5 py-2.5 text-sm text-white shadow-xl backdrop-blur-md">
        <div class="font-semibold">{name}</div>
        <div class="h-4 w-px bg-white/15" />
        <div class="text-neutral-300">
          Turn <span class="font-mono text-emerald-400">{turn + 1}</span>
          <span class="text-neutral-500"> / {maxTurns}</span>
        </div>
        <div class="h-4 w-px bg-white/15" />
        <div class="text-neutral-300">
          {myName} <span class="text-neutral-500">({role})</span>
          {oppName && <span class="text-neutral-500"> vs {oppName}</span>}
        </div>
        <div class="h-4 w-px bg-white/15" />
        {waiting ? (
          <div class="flex items-center gap-2 text-yellow-300">
            <span class="inline-block h-2 w-2 animate-pulse rounded-full bg-yellow-400" />
            Waiting for opponent…
          </div>
        ) : (
          <div class="text-emerald-300">Place a unit, then SUBMIT</div>
        )}
      </div>
    </div>
  );
}

function RematchButtons({ hostId, name }: { hostId: string; name: string }) {
  const [busy, setBusy] = useState(false);
  const rematch = async () => {
    setBusy(true);
    try {
      const m = await createMatch({
        name: name || "Rematch",
        visibility: "public",
        hostId,
      });
      window.location.href = `${BASE_URL}/multiplayer/play?id=${encodeURIComponent(m.id)}`;
    } catch {
      setBusy(false);
    }
  };
  return (
    <div class="flex gap-2">
      <button
        type="button"
        onClick={rematch}
        disabled={busy}
        class="flex-1 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-black hover:bg-emerald-400 disabled:opacity-50"
      >
        {busy ? "…" : "Rematch"}
      </button>
      <a
        href={`${BASE_URL}/multiplayer`}
        class="flex-1 rounded-lg border border-neutral-700 px-4 py-2 text-center text-sm font-semibold text-neutral-300 hover:border-neutral-500"
      >
        Lobbies
      </a>
    </div>
  );
}

function CopyField({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      // clipboard blocked — the field is still selectable
    }
  };
  return (
    <div>
      <div class="text-xs text-neutral-500">{label}</div>
      <div class="mt-1 flex gap-2">
        <input
          readOnly
          value={value}
          onFocusCapture={(e) => (e.target as HTMLInputElement).select()}
          class={`flex-1 rounded-lg border border-neutral-800 bg-neutral-950 px-3 py-1.5 text-sm text-white ${
            mono ? "font-mono uppercase tracking-widest" : ""
          }`}
        />
        <button
          type="button"
          onClick={copy}
          class="rounded-lg border border-neutral-700 px-3 py-1.5 text-xs font-semibold text-neutral-300 hover:border-emerald-400 hover:text-emerald-300"
        >
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
    </div>
  );
}

function Overlay({ children }: { children: preact.ComponentChildren }) {
  return (
    <div class="fixed inset-x-0 bottom-0 top-12 z-30 flex items-center justify-center bg-black/70 backdrop-blur-sm">
      {children}
    </div>
  );
}

function Card({
  title,
  children,
}: {
  title: string;
  children: preact.ComponentChildren;
}) {
  return (
    <div class="flex w-full max-w-md flex-col gap-4 rounded-xl border border-white/10 bg-neutral-900/95 p-8 shadow-2xl">
      <h2 class="text-xl font-bold text-white">{title}</h2>
      {children}
    </div>
  );
}

function BackToLobbiesButton() {
  return (
    <a
      href={`${BASE_URL}/multiplayer`}
      class="self-start text-xs text-neutral-400 hover:text-white"
    >
      ← Back to lobbies
    </a>
  );
}
