// Darts – Service Worker für Offline-Start und zuverlässige Updates.
//
// Strategie „Netz zuerst, Cache als Rückfall“:
// - Jede Datei der App wird beim Server nachgefragt (bedingte Anfrage, `cache: 'no-cache'`).
//   Ist sie unverändert, antwortet der Server kurz mit 304 – ist sie neu, kommt die neue.
//   Damit kommen Updates beim nächsten Start bzw. Neuladen sicher an (kein ewiger alter Cache).
// - Jede erfolgreiche Antwort landet im Cache. Ohne Netz (Fehler) liefert der Cache – die App startet offline.
// - Seitenaufruf (index.html): Antwortet das Netz nicht binnen NAV_TIMEOUT_MS, kommt die Kopie aus dem Cache
//   (schwaches Netz soll den Start nicht blockieren).
// - Nicht gecacht: WebSocket /ws, /version.json, /health, /apk/… (immer live vom Server).
//
// Die Seite schickt nach dem Start die Liste der bereits geladenen Dateien (Nachricht 'cache'),
// damit auch der allererste Besuch komplett offline verfügbar wird.

const CACHE = 'darts-app-v1';
const NAV_TIMEOUT_MS = 4000;
const SHELL = ['./', 'flutter_bootstrap.js', 'manifest.json', 'icons/splash.png', 'favicon.png'];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(SHELL.map((u) => cache.add(new Request(u, { cache: 'no-cache' })).catch(() => {})))
    )
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => k.startsWith('darts-') && k !== CACHE).map((k) => caches.delete(k)));
      await self.clients.claim();
    })()
  );
});

function scopePath() {
  return new URL(self.registration.scope).pathname;
}

function shouldHandle(url) {
  if (url.origin !== self.location.origin) return false;
  const p = url.pathname.substring(scopePath().length - 1);
  if (p === '/sw.js' || p === '/flutter_service_worker.js') return false;
  if (p === '/version.json' || p === '/health' || p.startsWith('/ws') || p.startsWith('/apk/')) return false;
  return true;
}

async function fromNetwork(request) {
  const res = await fetch(request, { cache: 'no-cache' });
  if (res && res.status === 200 && res.type === 'basic') {
    const copy = res.clone();
    caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {});
  }
  return res;
}

async function fromCache(request, isNav) {
  const cache = await caches.open(CACHE);
  let hit = await cache.match(request, { ignoreSearch: isNav });
  if (!hit && isNav) hit = (await cache.match('./')) || (await cache.match('index.html'));
  return hit;
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (!shouldHandle(url)) return;
  const isNav = req.mode === 'navigate';

  event.respondWith(
    (async () => {
      const net = fromNetwork(req);
      if (isNav) {
        // Seitenaufruf: höchstens NAV_TIMEOUT_MS auf das Netz warten, wenn eine Kopie da ist.
        const cached = await fromCache(req, true);
        if (cached) {
          const timeout = new Promise((resolve) => setTimeout(() => resolve(null), NAV_TIMEOUT_MS));
          const res = await Promise.race([net.catch(() => null), timeout]);
          return res || cached;
        }
      }
      try {
        return await net;
      } catch (e) {
        const cached = await fromCache(req, isNav);
        if (cached) return cached;
        throw e;
      }
    })()
  );
});

// Die Seite meldet, welche Dateien sie schon geladen hat → in den Cache legen (für Offline-Start).
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'cache' && Array.isArray(data.urls)) {
    event.waitUntil(
      (async () => {
        const cache = await caches.open(CACHE);
        for (const u of data.urls) {
          try {
            const url = new URL(u, self.registration.scope);
            if (!shouldHandle(url)) continue;
            if (await cache.match(url.href)) continue;
            const res = await fetch(url.href);
            if (res.status === 200 && res.type === 'basic') await cache.put(url.href, res);
          } catch (e) {
            // einzelne Datei fehlt – egal
          }
        }
      })()
    );
  }
});
