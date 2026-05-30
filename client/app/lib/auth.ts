import { signal } from "@preact/signals";
import type { User } from "@supabase/supabase-js";
import { supabase } from "./supabase";

const isBrowser = typeof window !== "undefined";

function getCachedUser(): User | null {
  if (!isBrowser) return null;
  try {
    const ref = new URL(import.meta.env.PUBLIC_SUPABASE_URL).hostname.split(
      ".",
    )[0];
    const stored = localStorage.getItem(`sb-${ref}-auth-token`);
    if (!stored) return null;
    return JSON.parse(stored)?.user ?? null;
  } catch {
    return null;
  }
}

export const authUser = signal<User | null>(getCachedUser());
// `authUser` is initially seeded from localStorage so the navbar doesn't
// flash an "Account" label on every page load — but that value can lie:
// the session may have expired, or supabase may be unreachable. Callers
// that gate behavior on "is this user actually signed in" must wait for
// authLoading to flip false before trusting authUser. Once that happens,
// authUser reflects the server's answer (or null if we couldn't get one).
export const authLoading = signal<boolean>(true);

if (isBrowser) {
  supabase.auth
    .getSession()
    .then(({ data, error }) => {
      if (error) {
        console.warn("[auth] getSession error:", error.message);
        authUser.value = null;
        return;
      }
      authUser.value = data.session?.user ?? null;
      // Bind realtime to the session token. Without this, the realtime
      // WebSocket connects as `anon` and any RLS policy gated on
      // `to authenticated` silently filters its broadcasts down to zero.
      if (data.session) supabase.realtime.setAuth(data.session.access_token);
    })
    .catch((e) => {
      // Network failure (supabase offline, DNS, CORS, etc.). We can't
      // verify the cached user, so we treat them as signed out — the
      // alternative is letting a stale localStorage value gate protected
      // pages, which is worse.
      console.warn("[auth] getSession failed:", e);
      authUser.value = null;
    })
    .finally(() => {
      authLoading.value = false;
    });

  supabase.auth.onAuthStateChange((_event, session) => {
    authUser.value = session?.user ?? null;
    // Once we hear from onAuthStateChange the loading window is over —
    // covers the case where getSession() races onAuthStateChange in
    // either direction.
    authLoading.value = false;

    if (session) {
      supabase.realtime.setAuth(session.access_token);
      document.cookie = `sb-access-token=${session.access_token}; path=/; SameSite=Lax`;
      document.cookie = `sb-refresh-token=${session.refresh_token}; path=/; SameSite=Lax`;
    } else {
      document.cookie = "sb-access-token=; path=/; Max-Age=0";
      document.cookie = "sb-refresh-token=; path=/; Max-Age=0";
      // Tell godot-bridge.js to flush the cached sandbox snapshot so an
      // anonymous visitor on the same browser doesn't load this user's scene.
      window.dispatchEvent(new CustomEvent("auth-signed-out"));
    }
  });
}
