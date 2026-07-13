import { useEffect, useState } from "preact/hooks";
import { supabase } from "@/lib/supabase";
import { BASE_URL } from "@/utils";

type Status = "checking" | "ready" | "invalid" | "done";

export default function ResetPasswordForm() {
  const [status, setStatus] = useState<Status>("checking");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // Clicking the emailed link lands here with the recovery tokens in the URL.
  // The supabase client (detectSessionInUrl) exchanges them for a temporary
  // session and fires a PASSWORD_RECOVERY event. We also check getSession()
  // directly in case that exchange already finished before we subscribed.
  useEffect(() => {
    let settled = false;
    const markReady = () => {
      if (settled) return;
      settled = true;
      setStatus("ready");
    };

    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "PASSWORD_RECOVERY" || session) markReady();
    });

    supabase.auth.getSession().then(({ data }) => {
      if (data.session) markReady();
    });

    // If neither the URL exchange nor an existing session produced a session,
    // the link is missing, malformed, or expired.
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        setStatus("invalid");
      }
    }, 4000);

    return () => {
      sub.subscription.unsubscribe();
      clearTimeout(timer);
    };
  }, []);

  const handleSubmit = async (e: Event) => {
    e.preventDefault();
    setError("");
    if (password !== confirm) {
      setError("Passwords do not match.");
      return;
    }
    setSubmitting(true);
    const { error: updateError } = await supabase.auth.updateUser({ password });
    if (updateError) {
      setError(updateError.message);
      setSubmitting(false);
      return;
    }
    setStatus("done");
    setSubmitting(false);
  };

  if (status === "checking") {
    return <div class="text-neutral-500">Verifying reset link...</div>;
  }

  if (status === "invalid") {
    return (
      <div class="flex flex-col gap-4 text-center">
        <p class="text-white font-medium">
          This reset link is invalid or has expired.
        </p>
        <p class="text-sm text-neutral-400">
          Request a new one from the sign-in screen.
        </p>
        <a
          href={`${BASE_URL}/`}
          class="px-4 py-3 bg-neutral-800 hover:bg-neutral-700 border border-neutral-700 text-white rounded-lg transition-colors text-sm"
        >
          Back to home
        </a>
      </div>
    );
  }

  if (status === "done") {
    return (
      <div class="flex flex-col gap-4 text-center">
        <div class="mx-auto w-12 h-12 rounded-full bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400 text-xl">
          &#10003;
        </div>
        <p class="text-white font-medium">Password updated</p>
        <p class="text-sm text-neutral-400">
          Your password has been changed. You're now signed in.
        </p>
        <a
          href={`${BASE_URL}/`}
          class="px-4 py-3 bg-emerald-500 hover:bg-emerald-400 text-black font-semibold rounded-lg transition-colors"
        >
          Continue
        </a>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} class="flex flex-col gap-4">
      <p class="text-sm text-neutral-400">
        Enter a new password for your account.
      </p>
      <input
        type="password"
        placeholder="New password"
        value={password}
        onInput={(e) => setPassword((e.target as HTMLInputElement).value)}
        class="px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-emerald-500"
        required
        minLength={6}
      />
      <input
        type="password"
        placeholder="Confirm new password"
        value={confirm}
        onInput={(e) => setConfirm((e.target as HTMLInputElement).value)}
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
        {submitting ? "..." : "Update password"}
      </button>
    </form>
  );
}
