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
export const authLoading = signal(false);

if (isBrowser) {
  supabase.auth.getSession().then(({ data: { session } }) => {
    authUser.value = session?.user ?? null;
  });

  supabase.auth.onAuthStateChange((_event, session) => {
    authUser.value = session?.user ?? null;

    if (session) {
      document.cookie = `sb-access-token=${session.access_token}; path=/; SameSite=Lax`;
      document.cookie = `sb-refresh-token=${session.refresh_token}; path=/; SameSite=Lax`;
    } else {
      document.cookie = "sb-access-token=; path=/; Max-Age=0";
      document.cookie = "sb-refresh-token=; path=/; Max-Age=0";
    }
  });
}
