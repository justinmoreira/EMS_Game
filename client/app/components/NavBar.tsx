export default function NavBar() {
  return (
    <nav class="fixed top-0 left-0 right-0 z-50 bg-neutral-900/80 backdrop-blur-sm border-b border-neutral-700">
      <div class="flex items-center justify-between px-6 h-12">
        <span class="text-sm font-bold tracking-wide">EMS Sim</span>
        <div class="flex items-center gap-6">
          <a href="/play" class="text-sm font-medium hover:text-white text-neutral-300 transition-colors">Singleplayer</a>
          <a href="/multiplayer" class="text-sm font-medium hover:text-white text-neutral-300 transition-colors">Multiplayer</a>
          <a href="/leaderboards" class="text-sm font-medium hover:text-white text-neutral-300 transition-colors">Leaderboards</a>
        </div>
        <a href="/account" class="text-sm font-medium hover:text-white text-neutral-300 transition-colors">Account</a>
      </div>
    </nav>
  );
}
