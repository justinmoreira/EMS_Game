// Godot <-> JS bridge. Loaded synchronously on /play before the Godot
// engine boots, so anything Godot calls from _ready (JavaScriptBridge.eval)
// must be defined here — not in TS-bundled modules which load deferred.

// Tutorial reset trigger from the web UI.
window.initTutorialListener = function () {
  window.addEventListener('progress-changed', function (e) {
    if (window._tutDone === true && !e.detail.tutorial_complete) {
      location.reload();
    }
    window._tutDone = e.detail.tutorial_complete;
  });
};

// Sandbox save/load (localStorage layer). Synchronous and always available
// so Godot's restore-on-_ready never races a deferred module.
// Durability (Dexie) and cloud sync (Supabase) attach in sandbox.ts via the
// "sandbox-saved" event below.
//
// Anon users get the localStorage + Dexie tiers for free — only the
// Supabase fan-out is auth-gated (inside sandbox.ts's syncSlot). Signing
// out clears the localStorage snapshot so the next anon visitor on the
// same browser doesn't see the previous user's scene.
(function () {
  var KEY = 'sandbox_current';

  window.getSandbox = function () {
    try {
      return localStorage.getItem(KEY) || '';
    } catch (_e) {
      return '';
    }
  };

  window.saveSandbox = function (json, mode) {
    // Each persister Node passes its own mode ("sandbox", "mission", ...).
    // Default keeps single-mode callers (and old code) working.
    mode = mode || 'sandbox';
    try {
      localStorage.setItem(KEY, json);
    } catch (_e) {
      // Quota / private mode — best-effort, snapshot still lives in memory.
    }
    // Hand off to anything (sandbox.ts) that wants to durably persist it.
    window.dispatchEvent(
      new CustomEvent('sandbox-saved', {
        detail: { json: json, mode: mode },
      }),
    );
  };

  window.addEventListener('auth-signed-out', function () {
    try {
      localStorage.removeItem(KEY);
    } catch (_e) {}
  });
})();
