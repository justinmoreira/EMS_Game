import type { RealtimeChannel } from "@supabase/supabase-js";
import { useEffect, useRef, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import { type CollabRoom, joinRoom, persistSnapshot } from "@/lib/collab";
import { getProfiles } from "@/lib/profile";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";

// Realtime transport + presence overlay for a collaborative sandbox room.
//
// This component is a mostly-dumb pipe: Godot owns the scene and the per-unit
// merge logic, and talks to it through the bridge (window.coopApplyOp, etc.).
// Our jobs are (1) publish the room to `window` so the engine can seed shared
// terrain before boot, (2) relay per-unit ops between the two clients over a
// Realtime broadcast channel, (3) elect the host to persist the durable board
// snapshot, and (4) show a lightweight "share invite / partner status" HUD.
//
// The op payloads are opaque strings minted by Godot — we never parse them.

declare global {
  interface Window {
    COLLAB_ROOM?: {
      id: string;
      seed: number;
      host_id: string | null;
      guest_id: string | null;
    };
    COLLAB_PLAYER_ID?: string;
    COLLAB_IS_HOST?: boolean;
    COLLAB_SNAPSHOT?: string;
    // Set by us, called by the bridge trampolines.
    __coopBroadcastOp?: (opJson: string) => void;
    __coopPersistSnapshot?: (json: string) => void;
    // Set by Godot (BaseLevel), called by us on inbound ops.
    coopApplyOp?: (opJson: string) => void;
  }
}

function getRoomId(): string {
  if (typeof window === "undefined") return "";
  return new URLSearchParams(window.location.search).get("id") ?? "";
}

function snapshotString(room: CollabRoom): string {
  const s = room.state_json;
  return typeof s === "string" ? s : JSON.stringify(s);
}

export default function CoopRoom() {
  const user = authUser.value;
  const roomId = getRoomId();
  const [room, setRoom] = useState<CollabRoom | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [partnerOnline, setPartnerOnline] = useState(false);
  const [partnerName, setPartnerName] = useState<string>("");
  const [copied, setCopied] = useState<string>("");
  const [dismissed, setDismissed] = useState(false);

  const channelRef = useRef<RealtimeChannel | null>(null);
  const persistTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latestSnapshot = useRef<string>("");

  // Publish the room to `window` so the play page's boot gate resolves and the
  // engine seeds shared terrain. Kept in a ref-free effect so it re-runs if the
  // row changes (e.g. guest joins -> active).
  const publish = (r: CollabRoom, playerId: string) => {
    window.COLLAB_ROOM = {
      id: r.id,
      seed: r.seed,
      host_id: r.host_id,
      guest_id: r.guest_id,
    };
    window.COLLAB_PLAYER_ID = playerId;
    window.COLLAB_IS_HOST = r.host_id === playerId;
    // Only seed the restore snapshot once, at first publish — after boot Godot
    // owns the live scene and re-stashing would fight the merge.
    if (window.COLLAB_SNAPSHOT === undefined) {
      window.COLLAB_SNAPSHOT = snapshotString(r);
    }
  };

  // Fetch the room, auto-joining the empty guest seat if we arrived via an
  // invite link and aren't a participant yet. Race-safe via the join_collab RPC.
  useEffect(() => {
    if (authLoading.value) return;
    if (!user) {
      setLoading(false);
      setError("Sign in (top right) to enter this co-op room.");
      return;
    }
    if (!roomId) {
      setLoading(false);
      setError("No room id in the URL.");
      return;
    }
    // We have a signed-in user and a room id: clear any stale error (e.g. the
    // "Sign in…" prompt shown before auth resolved) and show loading while we
    // fetch, so the banner disappears the moment the user signs in.
    setError("");
    setLoading(true);
    let cancelled = false;
    (async () => {
      let { data } = await supabase
        .from("collab_rooms")
        .select("*")
        .eq("id", roomId)
        .maybeSingle();

      // Not a participant and there's an open seat (or it's private and hidden):
      // claim it, then re-read.
      const participant =
        data && (data.host_id === user.id || data.guest_id === user.id);
      if (!participant) {
        const res = await joinRoom(roomId);
        if (!res.ok) {
          if (!cancelled) {
            setError(res.error ?? "Could not join this room.");
            setLoading(false);
          }
          return;
        }
        const reread = await supabase
          .from("collab_rooms")
          .select("*")
          .eq("id", roomId)
          .maybeSingle();
        data = reread.data;
      }

      if (cancelled) return;
      if (!data) {
        setError("Room not found.");
        setLoading(false);
        return;
      }
      publish(data, user.id);
      setRoom(data);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id, roomId, authLoading.value]);

  // Wire the bridge implementations + the realtime channel once we have a room.
  useEffect(() => {
    if (!room || !user) return;
    const isHost = room.host_id === user.id;

    const channel = supabase.channel(`coop-${room.id}`, {
      config: { presence: { key: user.id } },
    });
    channelRef.current = channel;

    // Outbound: Godot -> here -> partner. Broadcast doesn't echo to sender, so
    // the partner (and only the partner) receives it.
    window.__coopBroadcastOp = (opJson: string) => {
      void channel.send({
        type: "broadcast",
        event: "op",
        payload: { from: user.id, op: opJson },
      });
    };

    // Durable persistence: only the host writes state_json, to avoid two
    // writers clobbering each other. Godot pushes the full merged board on its
    // own debounce; we debounce again (2s) before hitting the DB.
    if (isHost) {
      window.__coopPersistSnapshot = (json: string) => {
        latestSnapshot.current = json;
        if (persistTimer.current) clearTimeout(persistTimer.current);
        persistTimer.current = setTimeout(() => {
          let parsed: unknown;
          try {
            parsed = JSON.parse(latestSnapshot.current);
          } catch {
            return;
          }
          void persistSnapshot(room.id, parsed as never);
        }, 2000);
      };
    }

    channel
      // Inbound ops from the partner -> straight into Godot.
      .on(
        "broadcast",
        { event: "op" },
        (msg: { payload?: { from?: string; op?: string } }) => {
          const p = msg.payload;
          if (!p || p.from === user.id || typeof p.op !== "string") return;
          window.coopApplyOp?.(p.op);
        },
      )
      // Room row changes: guest joins (waiting -> active), name edits, etc.
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "collab_rooms",
          filter: `id=eq.${room.id}`,
        },
        (p: { new: CollabRoom }) => {
          setRoom(p.new);
          publish(p.new, user.id);
        },
      )
      // Presence: is the partner currently connected?
      .on("presence", { event: "sync" }, () => {
        const state = channel.presenceState();
        const others = Object.keys(state).filter((k) => k !== user.id);
        setPartnerOnline(others.length > 0);
      })
      .subscribe((status) => {
        if (status === "SUBSCRIBED") {
          void channel.track({ user_id: user.id });
        }
      });

    return () => {
      window.__coopBroadcastOp = undefined;
      window.__coopPersistSnapshot = undefined;
      if (persistTimer.current) clearTimeout(persistTimer.current);
      supabase.removeChannel(channel);
      channelRef.current = null;
    };
  }, [room?.id, user?.id]);

  // Resolve the partner's display name for the HUD.
  useEffect(() => {
    if (!room || !user) return;
    const partnerId = room.host_id === user.id ? room.guest_id : room.host_id;
    if (!partnerId) {
      setPartnerName("");
      return;
    }
    let cancelled = false;
    void getProfiles([partnerId]).then((map) => {
      if (!cancelled)
        setPartnerName(map.get(partnerId)?.display_name ?? "Partner");
    });
    return () => {
      cancelled = true;
    };
  }, [room?.host_id, room?.guest_id, user?.id]);

  if (loading) return null;
  if (error) {
    return (
      <div class="fixed inset-x-0 top-14 z-50 mx-auto w-fit max-w-[90vw] rounded-lg border border-red-500/40 bg-black/80 px-4 py-2 text-sm text-red-300 backdrop-blur">
        {error}{" "}
        <a href={`${BASE_URL}/coop`} class="ml-2 underline hover:text-white">
          Back to rooms
        </a>
      </div>
    );
  }
  if (!room) return null;

  const link = `${window.location.origin}${BASE_URL}/coop/play?id=${room.id}`;
  const hasPartner = !!room.guest_id;
  const copy = (text: string, label: string) => {
    void navigator.clipboard?.writeText(text);
    setCopied(label);
    setTimeout(() => setCopied(""), 1500);
  };

  // Minimal top HUD: while there's no partner yet, prompt to share the invite;
  // once both are in, show a live connected/away indicator. Dismissible so it
  // never gets in the way of the canvas.
  if (dismissed) return null;

  return (
    <div class="fixed inset-x-0 top-14 z-50 flex justify-center px-4 pointer-events-none">
      <div class="flex items-center gap-3 rounded-xl border border-white/10 bg-black/70 px-4 py-2 text-sm text-white shadow-lg backdrop-blur pointer-events-auto">
        <span class="font-medium">{room.name}</span>
        <span class="h-4 w-px bg-white/15" />
        {!hasPartner ? (
          <>
            <span class="text-neutral-300">Share to invite a partner:</span>
            <code class="rounded bg-neutral-800 px-2 py-0.5 font-mono tracking-widest text-emerald-300">
              {room.invite_code ?? room.id}
            </code>
            <button
              type="button"
              onClick={() => copy(room.invite_code ?? room.id, "code")}
              class="rounded-md border border-neutral-700 px-2 py-0.5 text-xs text-neutral-300 hover:border-emerald-500 hover:text-white"
            >
              {copied === "code" ? "Copied" : "Copy code"}
            </button>
            <button
              type="button"
              onClick={() => copy(link, "link")}
              class="rounded-md border border-neutral-700 px-2 py-0.5 text-xs text-neutral-300 hover:border-emerald-500 hover:text-white"
            >
              {copied === "link" ? "Copied" : "Copy link"}
            </button>
          </>
        ) : (
          <span class="flex items-center gap-2 text-neutral-300">
            <span
              class={`inline-block h-2 w-2 rounded-full ${
                partnerOnline ? "bg-emerald-500" : "bg-neutral-500"
              }`}
            />
            {partnerName || "Partner"} {partnerOnline ? "connected" : "away"}
          </span>
        )}
        <span class="h-4 w-px bg-white/15" />
        <button
          type="button"
          onClick={() => setDismissed(true)}
          title="Hide"
          class="text-neutral-400 hover:text-white"
        >
          ×
        </button>
      </div>
    </div>
  );
}
