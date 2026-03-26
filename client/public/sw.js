const CACHE_NAME = "ems-sim-v1";
const PRECACHE = [
  "./",
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
  event.respondWith(
    caches.match(event.request).then((cached) => {
      // Always fetch from network in the background to update cache
      const networkFetch = fetch(event.request).then((response) => {
        if (response.ok && event.request.method === "GET") {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      });
      // Serve cached version immediately, fall back to network
      return cached || networkFetch;
    })
  );
});
