// Findest Sport — Service Worker
// Strategy: network-first for HTML (biar deploy baru langsung sampai),
//           cache-first for fonts/JS libs (biar cepet + jalan offline).
// Skip Supabase API + wa.me + drive URLs — always network fresh.

const CACHE_VERSION = 'findest-v10';
const RUNTIME_CACHE = 'findest-runtime-v10';

const CORE_ASSETS = [
  './catalog.html',
  './admin-orders.html',
  './qr-generator.html',
  './manifest.json',
  './manifest-admin.json',
  './manifest-crm.json',
  './icon-192.svg',
  './icon-512.svg',
  './icon-maskable.svg'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_VERSION)
      .then((cache) => cache.addAll(CORE_ASSETS).catch(err => console.warn('[SW] cache warm failed:', err)))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== CACHE_VERSION && k !== RUNTIME_CACHE)
          .map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);

  // Skip non-GET
  if (req.method !== 'GET') return;

  // Never intercept Supabase, WhatsApp, Google Drive, YouTube
  if (
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('wa.me') ||
    url.hostname.includes('drive.google.com') ||
    url.hostname.includes('googleusercontent.com') ||
    url.hostname.includes('youtube.com') ||
    url.hostname.includes('youtu.be')
  ) return;

  // Network-first for HTML pages (deploy update langsung sampai)
  const acceptHeader = req.headers.get('accept') || '';
  if (req.mode === 'navigate' || acceptHeader.includes('text/html')) {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const clone = res.clone();
          caches.open(RUNTIME_CACHE).then((c) => c.put(req, clone)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req).then((cached) => cached || caches.match('./catalog.html')))
    );
    return;
  }

  // Cache-first for static assets (fonts, JS libs, images, SVG)
  e.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res.ok && (res.type === 'basic' || res.type === 'cors')) {
          const clone = res.clone();
          caches.open(RUNTIME_CACHE).then((c) => c.put(req, clone)).catch(() => {});
        }
        return res;
      });
    })
  );
});

// Optional: listen buat skip-waiting message dari page (biar update lgsg aktif)
self.addEventListener('message', (e) => {
  if (e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});
