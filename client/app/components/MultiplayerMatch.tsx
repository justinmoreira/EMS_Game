import { useEffect, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";
import type { Json, Tables } from "./../lib/database.types";

type MatchRow = Tables<"matches">;

declare global {
  interface Window {
    MULTIPLAYER_MATCH?: MatchRow;
    MULTIPLAYER_PLAYER_ID?: string;
    submitMpAction?: (boardJson?: string) => Promise<void>;
    godotApplyOpponentBoard?: (boardJson: string, ownerId: string) => void;
  }
}

type ActionRow = Tables<"match_actions">;

// Exposes the current match (id + seed + roles + turn) on `window` so the
// Godot side can read it via JavaScriptBridge.eval — that's how the `?id`
// query param becomes meaningful: it picks the row whose seed drives terrain
// gen and whose turn counter the SUBMIT button will write into.
function publishMatchToWindow(match: MatchRow | null) {
  if (typeof window === "undefined") return;
  if (match) window.MULTIPLAYER_MATCH = match;
  else delete window.MULTIPLAYER_MATCH;
}

// Mirrors auth.uid() to a plain global so Godot's Unit.gd can identify
// the local player without round-tripping through the JWT cookie. Used
// by the enemy-unit color inversion to decide which units to invert.
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
  // Opponent's submitted action, held until the turn it belongs to has
  // been completed (current_turn has moved past it). Applied by the
  // effect below — see WEGO note next to handleOpponentInsert.
  const [pendingOpponentAction, setPendingOpponentAction] =
    useState<ActionRow | null>(null);

  // Hard auth gate. Two halves:
  //   • While `verifying` is true we haven't confirmed the session with
  //     the server yet — the cached `user` could be stale (expired token,
  //     supabase offline). Do NOT make redirect decisions here.
  //   • Once `verifying` flips false, `user === null` is definitive:
  //     either the server said we're signed out, or we couldn't reach it
  //     and chose to fail-closed (see lib/auth.ts). Bounce to /singleplayer.
  useEffect(() => {
    if (verifying) return;
    if (user === null) {
      console.log("[mp/match] auth verification done, no user — redirecting to /singleplayer");
      window.location.href = `${BASE_URL}/singleplayer`;
    }
  }, [verifying, user]);

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
        if (data) {
          console.log(
            "[mp/match] fetched match",
            data.id,
            "seed=",
            data.seed,
            "turn=",
            data.current_turn,
            "status=",
            data.status,
          );
        } else {
          console.warn("[mp/match] fetch returned no row for id=", matchId);
        }
        setMatch(data);
        publishMatchToWindow(data);
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [matchId]);

  // Drop the global on unmount so navigating back to the lobby (or to
  // /sandbox) doesn't leave stale match data on `window`.
  useEffect(() => {
    return () => {
      publishMatchToWindow(null);
      publishPlayerIdToWindow(null);
    };
  }, []);

  // Mirror the auth uid to a JS global the moment we know it. Done in
  // its own effect so Godot can read it even before the match row lands.
  useEffect(() => {
    publishPlayerIdToWindow(user?.id ?? null);
  }, [user?.id]);

  // Wire the Godot-side SUBMIT button (Sidebar.gd → JavaScriptBridge.eval
  // → window.submitMpAction) to a real DB write. Each call inserts the
  // calling player's action for the current turn; the both-submitted
  // trigger (see 20260529000000_create_multiplayer.sql) advances
  // matches.current_turn once both rows land. PoC payload is opaque —
  // when the Godot side starts serializing real moves, it'll pass them
  // through this hook instead.
  useEffect(() => {
    if (!user || !match) {
      console.log(
        "[mp/submit] skipping publish — user?",
        !!user,
        "match?",
        !!match,
      );
      return;
    }
    console.log(
      "[mp/submit] publishing window.submitMpAction (turn=",
      match.current_turn,
      ")",
    );
    window.submitMpAction = async (boardJson?: string) => {
      console.log(
        "[mp/submit] inserting action for match",
        match.id,
        "turn",
        match.current_turn,
        "player",
        user.id.slice(0, 8),
        "board bytes:",
        boardJson?.length ?? 0,
      );
      // Parse the board snapshot here so the action payload stores it as
      // structured JSONB (queryable, indexable) instead of an escaped
      // string. Falls back to a flag-only payload if the board didn't
      // come through, so the turn-advance trigger still fires.
      let board: Json = null;
      if (boardJson) {
        try {
          board = JSON.parse(boardJson) as Json;
        } catch (e) {
          console.warn("[mp/submit] board JSON parse failed, dropping:", e);
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
        console.error("[mp/submit] insert FAILED:", error.message, error);
      } else {
        console.log("[mp/submit] insert OK — waiting on the other player");
      }
    };
    return () => {
      delete window.submitMpAction;
    };
  }, [user, match]);

  useEffect(() => {
    if (!matchId) return;
    // Wait for auth verification before subscribing: realtime.setAuth(token)
    // only takes effect on the NEXT channel created, so subscribing before
    // lib/auth.ts has called it leaves the channel pinned to the `anon`
    // role. RLS-gated broadcasts on these tables (`to authenticated`) then
    // silently drop every event despite the channel reporting SUBSCRIBED.
    // Verified by inspecting `realtime.subscription.claims_role`.
    if (verifying || !user) return;
    // Filters intentionally omitted while we diagnose: when filter
    // syntax mismatches the server's parser it silently drops every
    // event with no client-side error, masking the real cause. We
    // re-filter in JS below so a wildcard subscription is functionally
    // equivalent to the filtered one but lets us actually SEE traffic.
    // WEGO semantics: don't apply opponent's board the instant they
    // submit — that would give the player who hasn't yet submitted free
    // intel on the opponent's placement. Buffer the row here; the
    // pending-apply effect below waits until matches.current_turn ticks
    // forward (i.e. both have submitted) and only then pushes the
    // snapshot into Godot.
    const handleOpponentInsert = (payload: { new: ActionRow }) => {
      console.log(
        "[mp/match][raw] match_actions INSERT received:",
        payload.new,
      );
      const a = payload.new;
      if (a.match_id !== matchId) return;
      if (user && a.player_id === user.id) return;
      console.log(
        "[mp/match] buffering opponent action for turn",
        a.turn_number,
        "— will apply once matches.current_turn advances",
      );
      setPendingOpponentAction(a);
    };

    const handleMatchUpdate = (payload: { new: MatchRow }) => {
      console.log("[mp/match][raw] matches UPDATE received:", payload.new);
      const row = payload.new;
      if (row.id !== matchId) return;
      setMatch(row);
      publishMatchToWindow(row);
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
      .subscribe((status, err) => {
        if (err) {
          console.error(
            "[mp/match] channel error (",
            status,
            "):",
            err.message ?? err,
          );
        } else {
          console.log("[mp/match] channel status:", status);
        }
      });
    return () => {
      supabase.removeChannel(channel);
    };
    // `verifying` MUST be in the deps — when it flips false the previous
    // (anon) channel is torn down and a new one subscribes under the
    // authenticated session, which is when broadcasts actually start
    // arriving. Dropping it from deps reintroduces the silent-anon bug.
  }, [matchId, user?.id, verifying]);

  // WEGO commit: apply the buffered opponent board only after the DB
  // trigger has advanced past its turn (i.e. both players submitted).
  // The buffer + this effect together enforce "no peeking" — the
  // opponent's units stay invisible on your map until your own SUBMIT
  // has joined theirs to tick the turn.
  useEffect(() => {
    if (!match || !pendingOpponentAction) return;
    if (match.current_turn <= pendingOpponentAction.turn_number) return;

    const action = pendingOpponentAction.action as { board?: Json } | null;
    if (!action || action.board == null) {
      console.log(
        "[mp/match] pending opponent action has no board (turn=",
        pendingOpponentAction.turn_number,
        ") — dropping",
      );
      setPendingOpponentAction(null);
      return;
    }
    const fn = window.godotApplyOpponentBoard;
    if (typeof fn !== "function") {
      console.warn(
        "[mp/match] turn advanced + opponent board pending, but godotApplyOpponentBoard isn't registered yet — will retry once it is",
      );
      return;
    }
    console.log(
      "[mp/match] applying opponent board (turn=",
      pendingOpponentAction.turn_number,
      "→ current_turn=",
      match.current_turn,
      "owner=",
      pendingOpponentAction.player_id.slice(0, 8),
      ")",
    );
    fn(JSON.stringify(action.board), pendingOpponentAction.player_id);
    setPendingOpponentAction(null);
  }, [match?.current_turn, pendingOpponentAction]);

  // Block ALL match UI until the auth gate has resolved. While verifying
  // we don't know whether the user is actually signed in; once verified
  // and null, the redirect effect above is already firing — render a
  // brief holding card rather than the match flow so nothing leaks.
  if (verifying) {
    return (
      <Overlay>
        <Card title="Verifying session...">
          <p class="text-sm text-neutral-400">
            Checking your authentication with the server.
          </p>
        </Card>
      </Overlay>
    );
  }

  if (user === null) {
    return (
      <Overlay>
        <Card title="Signed out">
          <p class="text-sm text-neutral-400">
            Returning to singleplayer...
          </p>
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
        <Card title="Loading match...">
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
            exist. It may have been deleted.
          </p>
          <BackToLobbiesButton />
        </Card>
      </Overlay>
    );
  }

  // Once both seats are claimed, the trigger flips status to 'active' —
  // dismiss the overlay so the Godot canvas underneath is interactable.
  if (match.status === "active") return null;

  const isHost = user?.id === match.host_id;
  const isGuest = user?.id === match.guest_id;
  const role = isHost ? "Host (P1)" : isGuest ? "Guest (P2)" : "Spectator";

  return (
    <Overlay>
      <Card title="Waiting for second player...">
        <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
          <dt class="text-neutral-500">Lobby</dt>
          <dd class="font-mono text-white">{match.id}</dd>
          <dt class="text-neutral-500">Terrain seed</dt>
          <dd class="font-mono text-emerald-400">{match.seed}</dd>
          <dt class="text-neutral-500">You</dt>
          <dd class="text-white">{role}</dd>
        </dl>
        <div class="flex items-center gap-2 text-xs text-neutral-400">
          <span class="inline-block h-2 w-2 animate-pulse rounded-full bg-yellow-500" />
          Share this URL with the other player to fill the guest seat.
        </div>
        <BackToLobbiesButton />
      </Card>
    </Overlay>
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

