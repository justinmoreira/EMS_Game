import type { User } from "@supabase/supabase-js";
import { createPortal } from "preact/compat";
import { useEffect, useState } from "preact/hooks";
import { authLoading, authUser } from "@/lib/auth";
import { setProgress, syncStatus } from "@/lib/progress";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";

function LoginForm() {
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [pendingConfirmation, setPendingConfirmation] = useState<string | null>(
    null,
  );
  const [resending, setResending] = useState(false);
  const [resendInfo, setResendInfo] = useState("");

  const emailRedirectTo = `${window.location.origin}${BASE_URL}/`;

  const handleSubmit = async (e: Event) => {
    e.preventDefault();
    setError("");
    setSubmitting(true);
    if (mode === "login") {
      const { error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (authError) setError(authError.message);
    } else {
      const { data, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: { emailRedirectTo },
      });
      if (authError) {
        setError(authError.message);
      } else if (data.user && !data.session) {
        setPendingConfirmation(email);
      }
    }
    setSubmitting(false);
  };

  const handleResend = async () => {
    if (!pendingConfirmation) return;
    setResending(true);
    setResendInfo("");
    const { error: resendError } = await supabase.auth.resend({
      type: "signup",
      email: pendingConfirmation,
      options: { emailRedirectTo },
    });
    setResendInfo(
      resendError ? resendError.message : "Sent. Check your inbox.",
    );
    setResending(false);
  };

  if (pendingConfirmation) {
    return (
      <div class="flex flex-col gap-4 w-full text-center">
        <div class="mx-auto w-12 h-12 rounded-full bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400 text-xl">
          @
        </div>
        <p class="text-white font-medium">Check your email</p>
        <p class="text-sm text-neutral-400">
          We sent a confirmation link to{" "}
          <span class="text-white">{pendingConfirmation}</span>. Click it to
          activate your account, then come back here to sign in.
        </p>
        {resendInfo && <p class="text-xs text-neutral-400">{resendInfo}</p>}
        <button
          type="button"
          onClick={handleResend}
          disabled={resending}
          class="px-4 py-3 bg-neutral-800 hover:bg-neutral-700 border border-neutral-700 disabled:opacity-50 text-white rounded-lg transition-colors text-sm"
        >
          {resending ? "Sending..." : "Resend confirmation email"}
        </button>
        <button
          type="button"
          onClick={() => {
            setPendingConfirmation(null);
            setResendInfo("");
            setMode("login");
          }}
          class="text-sm text-neutral-400 hover:text-white transition-colors"
        >
          Back to sign in
        </button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} class="flex flex-col gap-4 w-full">
      <input
        type="email"
        placeholder="Email"
        value={email}
        onInput={(e) => setEmail((e.target as HTMLInputElement).value)}
        class="px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-emerald-500"
        required
      />
      <input
        type="password"
        placeholder="Password"
        value={password}
        onInput={(e) => setPassword((e.target as HTMLInputElement).value)}
        class="px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-emerald-500"
        required
        minLength={6}
      />
      {error && <p class="text-red-400 text-sm">{error}</p>}
      <button
        type="submit"
        disabled={submitting}
        class="px-4 py-3 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50 text-black font-semibold rounded-lg transition-colors"
      >
        {submitting ? "..." : mode === "login" ? "Sign In" : "Create Account"}
      </button>
      <button
        type="button"
        onClick={() => setMode(mode === "login" ? "signup" : "login")}
        class="text-sm text-neutral-400 hover:text-white transition-colors"
      >
        {mode === "login"
          ? "Don't have an account? Sign up"
          : "Already have an account? Sign in"}
      </button>
    </form>
  );
}

function ProfileView({ user }: { user: User }) {
  const currentName =
    (user.user_metadata?.display_name as string) ||
    user.email?.split("@")[0] ||
    "";
  const [editing, setEditing] = useState(false);
  const [displayName, setDisplayName] = useState(currentName);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    await supabase.auth.updateUser({ data: { display_name: displayName } });
    setSaving(false);
    setEditing(false);
  };

  const handleCancel = () => {
    setDisplayName(currentName);
    setEditing(false);
  };

  const handleSignOut = async () => {
    localStorage.removeItem("account_display_name");
    await supabase.auth.signOut();
  };

  return (
    <div class="flex flex-col gap-4 w-full">
      {editing ? (
        <div class="flex gap-2">
          <input
            type="text"
            value={displayName}
            onInput={(e) =>
              setDisplayName((e.target as HTMLInputElement).value)
            }
            class="flex-1 px-3 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-emerald-500"
          />
          <button
            type="button"
            onClick={handleSave}
            disabled={saving}
            class="px-3 py-2 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50 text-black font-semibold rounded-lg text-sm"
          >
            {saving ? "..." : "Save"}
          </button>
          <button
            type="button"
            onClick={handleCancel}
            class="px-3 py-2 bg-neutral-700 hover:bg-neutral-600 text-white rounded-lg text-sm"
          >
            Cancel
          </button>
        </div>
      ) : (
        <div class="relative w-full text-center">
          <span class="block text-center text-white text-lg font-medium">
            {currentName}
          </span>
          <button
            type="button"
            onClick={() => setEditing(true)}
            class="absolute right-0 top-1/2 -translate-y-1/2 text-neutral-500 hover:text-white transition-colors"
            title="Edit display name"
          >
            &#9998;
          </button>
        </div>
      )}
      <div class="text-neutral-500 text-xs">{user.email}</div>
      <div class="text-neutral-500 text-xs">
        Joined{" "}
        {user.created_at ? new Date(user.created_at).toLocaleDateString() : ""}
      </div>
      <button
        type="button"
        onClick={handleSignOut}
        class="px-4 py-3 bg-neutral-800 hover:bg-neutral-700 border border-neutral-700 text-white rounded-lg transition-colors"
      >
        Sign Out
      </button>
    </div>
  );
}

function getCachedName(): string {
  try {
    return localStorage.getItem("account_display_name") || "Account";
  } catch {
    return "Account";
  }
}

export default function AccountModal() {
  const [open, setOpen] = useState(false);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    setReady(true);
    const el = document.getElementById("account-placeholder");
    if (el) el.style.display = "none";
  }, []);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);
  const user = authUser.value;
  const displayName = user
    ? (user.user_metadata?.display_name as string) ||
      user.email?.split("@")[0] ||
      ""
    : "";
  useEffect(() => {
    if (displayName) localStorage.setItem("account_display_name", displayName);
  }, [displayName]);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        class="text-sm font-medium hover:text-white text-neutral-300 transition-colors min-w-[70px] text-right cursor-pointer"
      >
        {ready ? displayName || "Account" : getCachedName()}
      </button>
      {open &&
        createPortal(
          <div
            role="dialog"
            aria-modal="true"
            tabIndex={-1}
            class="fixed inset-0 z-[100] flex items-center justify-center bg-black/60"
            onClick={(e) => {
              if (e.target === e.currentTarget) setOpen(false);
            }}
            onKeyDown={(e) => {
              if (e.key === "Escape") setOpen(false);
            }}
          >
            <div class="w-full max-w-sm bg-neutral-900 border border-neutral-700 rounded-xl p-8 relative">
              <button
                type="button"
                onClick={() => setOpen(false)}
                class="absolute top-3 right-4 text-neutral-500 hover:text-white text-lg"
              >
                &times;
              </button>
              <h2 class="text-xl font-bold mb-6">
                {user ? "Account" : "Sign In"}
              </h2>
              {authLoading.value ? (
                <div class="text-neutral-500">Loading...</div>
              ) : user ? (
                <ProfileView user={user} />
              ) : (
                <LoginForm />
              )}
              <button
                type="button"
                onClick={() => {
                  setProgress({ tutorial_complete: false });
                  location.reload();
                }}
                class="w-full px-4 py-3 bg-neutral-800 hover:bg-neutral-700 border border-neutral-700 text-white rounded-lg transition-colors text-sm mt-4"
              >
                Tutorial
              </button>
              <div class="flex items-center gap-2 text-xs mt-4 pt-4 border-t border-neutral-700">
                <span
                  class={`inline-block w-2 h-2 rounded-full ${
                    syncStatus.value === "online"
                      ? "bg-emerald-500"
                      : syncStatus.value === "syncing"
                        ? "bg-yellow-500 animate-pulse"
                        : "bg-red-500"
                  }`}
                />
                <span class="text-neutral-500">
                  {syncStatus.value === "online"
                    ? "Synced"
                    : syncStatus.value === "syncing"
                      ? "Syncing..."
                      : "Offline"}
                </span>
              </div>
            </div>
          </div>,
          document.body,
        )}
    </>
  );
}
