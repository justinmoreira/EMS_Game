const CACHE_NAME = "ems-sim-v2";
const PRECACHE = [
  "./",
  "./play",
  "./manifest.json",
  "./godot/index.js",
  "./godot/index.wasm",
  "./godot/index.pck",
  "./godot/index.audio.worklet.js",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  // Skip non-GET and Supabase API calls
  if (request.method !== "GET" || request.url.includes("/rest/v1/") || request.url.includes("/auth/v1/")) {
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      const networkFetch = fetch(request)
        .then((response) => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
          }
          return response;
        })
        .catch(() => {
          // Offline fallback: serve index for navigation requests
          if (request.mode === "navigate") {
            return caches.match("./");
          }
          return cached;
        });

      // Serve cached immediately, update in background
      return cached || networkFetch;
    })
  );
});
