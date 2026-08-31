// Kitabi Admin service worker — the minimum that makes the console installable,
// and deliberately nothing more.
//
// The console is server-rendered and server-AUTHORITATIVE: every page is a live
// DB query and every action is a POST that mutates production. So this worker
// NEVER caches a page, a navigation, or an API response — a cached moderation
// queue is a wrong one, and you cannot approve a claim or run a merge offline
// anyway. Offline is meant to fail here, loudly, exactly as it would with no
// worker at all. The only thing cached is our own /static/ assets (already
// versioned with ?v=), which is a small load-time win with no correctness cost.
//
// Served from /sw.js (root) so its scope is the whole origin — see main.py.

const CACHE = "kitabi-admin-static-v1";

self.addEventListener("install", () => {
  // Take over on first load rather than waiting for every tab to close.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      // Drop caches from earlier CACHE versions.
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
      await self.clients.claim();
    })(),
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Only ever touch same-origin GETs under /static/. Everything else — pages,
  // POSTs, cross-origin fonts — falls through to the browser untouched.
  if (req.method !== "GET" || url.origin !== self.location.origin || !url.pathname.startsWith("/static/")) {
    return;
  }

  // Stale-while-revalidate: answer from cache instantly, refresh in the
  // background. Safe because /static/ URLs carry a ?v= that changes on edit.
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(req);
      const fresh = fetch(req)
        .then((res) => {
          if (res && res.ok) cache.put(req, res.clone());
          return res;
        })
        .catch(() => cached);
      return cached || fresh;
    })(),
  );
});
