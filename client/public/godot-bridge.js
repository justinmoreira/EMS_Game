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

// ── Co-op sandbox bridge ────────────────────────────────────────────────
// A collaborative sandbox room shares one live scene between two players.
// Godot drives three interactions from _ready onward, so the symbols must
// exist the moment this file loads (before Preact hydrates). CoopRoom.tsx
// wires the real implementations (window.__coop*) once the room row is
// fetched; these trampolines forward to them and no-op safely until then.
//
//   getCoopSnapshot()      Godot pulls the durable shared board on restore.
//                          CoopRoom.tsx stashes it on window.COLLAB_SNAPSHOT
//                          (the collab_rooms.state_json string) before boot.
//   coopSendOp(opJson)     Godot pushes ONE local per-unit op (upsert/delete
//                          /lock by stable uid) out to the partner.
//   coopSaveSnapshot(json) Godot pushes the full merged board for durable
//                          persistence (host election happens in CoopRoom).
window.getCoopSnapshot = function () {
  try {
    return window.COLLAB_SNAPSHOT || '';
  } catch (_e) {
    return '';
  }
};

window.coopSendOp = function (opJson) {
  if (typeof window.__coopBroadcastOp !== 'function') return;
  try {
    window.__coopBroadcastOp(opJson);
  } catch (e) {
    console.error('[bridge] coopSendOp threw:', e);
  }
};

window.coopSaveSnapshot = function (json) {
  if (typeof window.__coopPersistSnapshot !== 'function') return;
  try {
    window.__coopPersistSnapshot(json);
  } catch (e) {
    console.error('[bridge] coopSaveSnapshot threw:', e);
  }
};
