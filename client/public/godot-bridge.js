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

// Godot's SAVES button calls window.openSavesPicker(). Route it through an
// auth check: signed in → open the picker; signed out → open the sign-in
// modal (no point letting the user fiddle with saves they can't keep).
(function () {
  function isAuthed() {
    var cookies = document.cookie.split('; ');
    for (var i = 0; i < cookies.length; i++) {
      if (cookies[i].indexOf('sb-access-token=') === 0) {
        return cookies[i].length > 'sb-access-token='.length;
      }
    }
    return false;
  }

  window.openSavesPicker = function () {
    if (isAuthed()) {
      window.dispatchEvent(new CustomEvent('open-saves-picker'));
    } else {
      window.dispatchEvent(new CustomEvent('open-auth-modal'));
    }
  };
})();

// Multiplayer SUBMIT bridge. Defined here (alongside saveSandbox) instead
// of inside the React component so the symbol exists in the global scope
// the moment godot-bridge.js loads — Godot's JavaScriptBridge.eval can
// land here without racing Preact hydration. The real handler
// (window.submitMpAction) is wired up by MultiplayerMatch.tsx once the
// match row is fetched; this trampoline forwards to it and surfaces
// problems via console so a silent click is no longer ambiguous.
window.mpSubmitBoard = function (boardJson) {
  console.log(
    '[bridge] mpSubmitBoard called, payload bytes:',
    (boardJson || '').length,
  );
  if (typeof window.submitMpAction !== 'function') {
    console.warn(
      '[bridge] mpSubmitBoard: window.submitMpAction is not defined — Preact effect may not have run yet, or you are not signed in',
    );
    return;
  }
  try {
    var p = window.submitMpAction(boardJson);
    if (p && typeof p.then === 'function') {
      p.catch(function (e) {
        console.error('[bridge] mpSubmitBoard: submitMpAction rejected:', e);
      });
    }
  } catch (e) {
    console.error('[bridge] mpSubmitBoard: submitMpAction threw:', e);
  }
};
