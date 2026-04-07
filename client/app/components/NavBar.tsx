import type { User } from "@supabase/supabase-js";
import { authUser } from "@/lib/auth";
import { BASE_URL } from "@/utils";

export default function NavBar({ serverUser }: { serverUser?: User | null }) {
  const clientUser = authUser.value;
  const user = clientUser ?? serverUser;

  return (
    <nav class="fixed top-0 left-0 right-0 z-50 bg-neutral-900/80 backdrop-blur-sm border-b border-neutral-700">
      <div class="flex items-center justify-between px-6 h-12">
        <a href={`${BASE_URL}/`} class="text-sm font-bold tracking-wide">
          EMS Sim
        </a>
        <div class="flex items-center gap-6">
          <a
            href={`${BASE_URL}/play`}
            class="text-sm font-medium hover:text-white text-neutral-300 transition-colors"
          >
            Singleplayer
          </a>
          <a
            href={`${BASE_URL}/multiplayer`}
            class="text-sm font-medium hover:text-white text-neutral-300 transition-colors"
          >
            Multiplayer
          </a>
          <a
            href={`${BASE_URL}/leaderboards`}
            class="text-sm font-medium hover:text-white text-neutral-300 transition-colors"
          >
            Leaderboards
          </a>
        </div>
        <a
          href={`${BASE_URL}/account`}
          class="text-sm font-medium hover:text-white text-neutral-300 transition-colors"
        >
          {user
            ? (user.user_metadata?.display_name as string) ||
              user.email?.split("@")[0]
            : "Account"}
        </a>
      </div>
    </nav>
  );
}
