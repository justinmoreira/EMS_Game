import { BASE_URL } from "@/utils";

export default function NavBar() {
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
        <div class="flex items-center gap-4">
          <button
            type="button"
            onClick={() => {
              localStorage.removeItem("tutorial_complete");
              window.location.reload();
            }}
            class="text-xs font-medium hover:text-white text-neutral-500 transition-colors"
          >
            Reset Tutorial
          </button>
          <a
            href={`${BASE_URL}/account`}
            class="text-sm font-medium hover:text-white text-neutral-300 transition-colors"
          >
            Account
          </a>
        </div>
      </div>
    </nav>
  );
}
