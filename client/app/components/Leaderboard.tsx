import { useEffect, useState } from "preact/hooks";
import { authUser } from "@/lib/auth";
import { getLeaderboard, type Profile } from "@/lib/profile";

// Open leaderboard: every player ranked by wins, then fewest losses. Fetched
// once on mount (refresh to see the latest standings after matches finish).
export default function Leaderboard() {
  const user = authUser.value;
  const [rows, setRows] = useState<Profile[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    void getLeaderboard().then((data) => {
      if (!cancelled) setRows(data);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  if (rows === null) {
    return <p class="text-neutral-400">Loading rankings…</p>;
  }

  if (rows.length === 0) {
    return (
      <p class="text-neutral-400">
        No games played yet. Win a multiplayer match to top the board.
      </p>
    );
  }

  return (
    <div class="overflow-hidden rounded-xl border border-white/10 bg-black/45 backdrop-blur-md">
      <table class="w-full text-sm">
        <thead class="bg-white/5 text-xs uppercase tracking-wide text-neutral-400">
          <tr>
            <th class="px-6 py-3 text-left font-medium">#</th>
            <th class="px-6 py-3 text-left font-medium">Player</th>
            <th class="px-6 py-3 text-right font-medium">Wins</th>
            <th class="px-6 py-3 text-right font-medium">Losses</th>
            <th class="px-6 py-3 text-right font-medium">Draws</th>
            <th class="px-6 py-3 text-right font-medium">Played</th>
            <th class="px-6 py-3 text-right font-medium">Win %</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-white/5">
          {rows.map((p, i) => {
            const isMe = user?.id === p.id;
            const decided = p.wins + p.losses;
            const winPct =
              decided > 0 ? Math.round((p.wins / decided) * 100) : 0;
            return (
              <tr
                key={p.id}
                class={isMe ? "bg-emerald-500/10" : "hover:bg-white/5"}
              >
                <td class="px-6 py-3 font-mono text-neutral-400">{i + 1}</td>
                <td class="px-6 py-3 font-medium text-white">
                  {p.display_name || "Player"}
                  {isMe && (
                    <span class="ml-2 text-xs text-emerald-400">you</span>
                  )}
                </td>
                <td class="px-6 py-3 text-right font-mono text-emerald-300">
                  {p.wins}
                </td>
                <td class="px-6 py-3 text-right font-mono text-neutral-300">
                  {p.losses}
                </td>
                <td class="px-6 py-3 text-right font-mono text-neutral-400">
                  {p.draws}
                </td>
                <td class="px-6 py-3 text-right font-mono text-neutral-400">
                  {p.games_played}
                </td>
                <td class="px-6 py-3 text-right font-mono text-neutral-300">
                  {winPct}%
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
