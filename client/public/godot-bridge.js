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
  var KEY_PREFIX = 'sandbox_current';

  function keyFor(mode) {
    return KEY_PREFIX + ':' + (mode || 'sandbox');
  }

  window.getSandbox = function (mode) {
    try {
      return localStorage.getItem(keyFor(mode)) || '';
    } catch (_e) {
      return '';
    }
  };

  window.saveSandbox = function (json, mode) {
    // Each persister Node passes its own mode ("sandbox", "mission", ...).
    // Default keeps single-mode callers (and old code) working.
    mode = mode || 'sandbox';
    try {
      localStorage.setItem(keyFor(mode), json);
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
      // Mode-agnostic: clear every sandbox_current:* key so no mode is left
      // showing the previous user's scene to the next anon visitor.
      var toRemove = [];
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && k.indexOf(KEY_PREFIX + ':') === 0) toRemove.push(k);
      }
      for (var j = 0; j < toRemove.length; j++) {
        localStorage.removeItem(toRemove[j]);
      }
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
