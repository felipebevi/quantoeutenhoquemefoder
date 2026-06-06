/* Service worker — cache dos assets + lib de OCR (offline), mas SEM travar updates.
   Estratégia:
   - HTML/navegação  → NETWORK-FIRST (sempre pega a versão nova do app; cai no cache se offline)
   - demais assets   → STALE-WHILE-REVALIDATE (rápido e atualiza em background)
   Bump CACHE a cada release para limpar versões antigas. */
const CACHE = 'qtqmf-v3';
const ASSETS = ['./', './index.html', './manifest.json', './icon.svg', './icon-192.png',
                './icon-512.png', './apple-touch-icon.png', './economias.json'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const isHTML = req.mode === 'navigate' || req.destination === 'document' ||
                 url.pathname.endsWith('/') || url.pathname.endsWith('/index.html');
  // economias.json é atualizado pelo cron → também queremos sempre o mais novo
  const isRates = url.pathname.endsWith('/economias.json');

  if (isHTML || isRates) {
    // NETWORK-FIRST: sempre tenta a versão mais recente; cai no cache se offline.
    const key = isHTML ? './index.html' : './economias.json';
    e.respondWith(
      fetch(req)
        .then(res => {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(key, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(key).then(r => r || (isHTML ? caches.match('./') : r)))
    );
    return;
  }

  // Demais assets (inclui Tesseract no jsDelivr): stale-while-revalidate.
  const cacheable = url.origin === location.origin ||
                    url.href.includes('cdn.jsdelivr.net/npm/tesseract');
  e.respondWith(
    caches.match(req).then(hit => {
      const net = fetch(req).then(res => {
        if (cacheable && res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => hit);
      return hit || net;
    })
  );
});
