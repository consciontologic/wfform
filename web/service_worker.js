/* Complete, content-verified release shells. No API/configuration/runtime response cache. */
const VERSION = '__BUILD_ID__';
const CACHE = 'free-model-studio-__BUILD_ID__';
const MANIFEST = __PRECACHE_MANIFEST__;
const PREFIX = 'free-model-studio-';
const CLIENTS = PREFIX + 'clients-v2';
const SCOPE = new URL(self.registration.scope);
const releaseUrl = (version, path) => new URL('__releases/' + version + '/' + path, SCOPE).href;
const markerUrl = version => releaseUrl(version, 'release.json');
const isVersion = value => /^[a-f0-9]{64}$/.test(value);
const isGeneration = key => key.startsWith('free-model-studio-') && key !== CLIENTS;
let cleanup = Promise.resolve();

async function report(message) {
  for (const client of await self.clients.matchAll({includeUncontrolled: true})) {
    client.postMessage({type: 'PWA_ERROR', message: String(message).slice(0, 500)});
  }
}
async function verified(response, expected) {
  if (!response || !response.ok || response.type === 'opaque') return null;
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength !== expected.bytes) return null;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const hash = Array.from(new Uint8Array(digest), value => value.toString(16).padStart(2, '0')).join('');
  if (hash !== expected.sha256) return null;
  // Fetch exposes decoded bytes. Do not carry compression/length headers from
  // the wire onto the newly constructed decoded response (for gzip hosts).
  const headers = new Headers(response.headers);
  headers.delete('Content-Encoding');
  headers.delete('Content-Length');
  return new Response(bytes, {status: 200, headers});
}
async function reusable(path, expected, generations) {
  for (const name of generations) {
    const oldVersion = name.slice(PREFIX.length);
    const oldCache = await caches.open(name);
    // Legacy shells use root URLs. New releases are immutable and versioned.
    if (isVersion(oldVersion) && !(await oldCache.match(markerUrl(oldVersion)))) continue;
    const url = isVersion(oldVersion) ? releaseUrl(oldVersion, path) : new URL(path, SCOPE).href;
    const response = await oldCache.match(url);
    if (!response) continue;
    const copy = await verified(response, expected);
    if (copy) return copy;
  }
  return null;
}
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const abort = new AbortController();
    const workers = [];
    try {
      const cache = await caches.open(CACHE);
      const generations = (await caches.keys()).filter(isGeneration).reverse().slice(0, 8);
      const entries = Object.entries(MANIFEST);
      let cursor = 0, reusedAssets = 0, reusedBytes = 0, fetchedAssets = 0, fetchedBytes = 0;
      for (let lane = 0; lane < Math.min(3, entries.length); lane++) {
        workers.push((async () => {
          while (cursor < entries.length) {
            const [path, expected] = entries[cursor++];
            let response = await reusable(path, expected, generations);
            if (response) { reusedAssets++; reusedBytes += expected.bytes; }
            else {
              response = await verified(await fetch(new Request(releaseUrl(VERSION, path), {
                cache: 'force-cache', credentials: 'omit', signal: abort.signal,
              })), expected);
              // An HTTP cache can hold a corrupt immutable response. One bounded
              // cache-bypass fetch lets an explicit later check recover a repair.
              if (!response) response = await verified(await fetch(new Request(releaseUrl(VERSION, path), {
                cache: 'reload', credentials: 'omit', signal: abort.signal,
              })), expected);
              if (!response) throw new Error('Release integrity check failed for ' + path);
              fetchedAssets++; fetchedBytes += expected.bytes;
            }
            await cache.put(releaseUrl(VERSION, path), response);
          }
        })());
      }
      await Promise.all(workers);
      // Completion marker is last. Incomplete generations are never served/reused.
      await cache.put(markerUrl(VERSION), new Response(JSON.stringify({
        format: 2, version: VERSION, assets: MANIFEST,
        install: {reusedAssets, reusedBytes, fetchedAssets, fetchedBytes},
      }), {headers: {'Content-Type': 'application/json'}}));
      // Wait for the application's explicit APPLY_UPDATE; never force activation.
    } catch (error) {
      abort.abort();
      await Promise.allSettled(workers);
      await caches.delete(CACHE);
      await report('Unable to prepare a complete offline release: ' + error);
      throw error;
    }
  })());
});

async function prune() {
  const metadata = await caches.open(CLIENTS);
  const clients = (await self.clients.matchAll({type: 'window', includeUncontrolled: true}))
    .filter(client => client.url.startsWith(SCOPE.href));
  const live = new Set(clients.map(client => new URL('__pwa__/clients/' + client.id, SCOPE).href));
  const keep = new Set([CACHE]);
  let unknown = false;
  for (const key of live) {
    const record = await metadata.match(key);
    const version = record ? await record.text() : '';
    if (isVersion(version)) keep.add(PREFIX + version);
    else unknown = true;
  }
  for (const key of await metadata.keys()) {
    if (!live.has(key.url)) await metadata.delete(key);
  }
  // A sleeping or legacy tab may not identify its release. Defer deletion until
  // it identifies itself or closes; never sacrifice an open tab to a cache cap.
  if (unknown) return;
  const generations = (await caches.keys()).filter(isGeneration);
  const previous = generations.filter(key => key !== CACHE).at(-1);
  if (previous) keep.add(previous);
  await Promise.all(generations.filter(key => !keep.has(key)).map(key => caches.delete(key)));
}
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    if (!(await cache.match(markerUrl(VERSION)))) throw new Error('Offline release is incomplete.');
    await self.clients.claim();
    // CLIENT_RELEASE reports after controllerchange prune only unreferenced shells.
  })());
});
self.addEventListener('message', event => {
  if (event.data?.type === 'APPLY_UPDATE') event.waitUntil(self.skipWaiting());
  if (event.data?.type === 'CLIENT_RELEASE' && isVersion(event.data.release) && event.source?.id) {
    event.waitUntil((async () => {
      const metadata = await caches.open(CLIENTS);
      await metadata.put(new URL('__pwa__/clients/' + event.source.id, SCOPE).href,
        new Response(event.data.release));
      cleanup = cleanup.catch(() => {}).then(prune);
      await cleanup;
    })().catch(error => report('Offline release cleanup failed: ' + error)));
  }
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== SCOPE.origin ||
      request.headers.has('authorization') || url.search ||
      url.pathname.includes('/config/')) return;
  if (!url.pathname.startsWith(SCOPE.pathname)) return;
  let relative;
  try { relative = decodeURI(url.pathname.slice(SCOPE.pathname.length)); }
  catch (_) { return; }
  const versioned = /^__releases\/([a-f0-9]{64})\/(.+)$/.exec(relative);
  const navigation = request.mode === 'navigate' && (relative === '' || relative === 'index.html');
  if (!versioned && !navigation && !Object.hasOwn(MANIFEST, relative)) return;
  event.respondWith((async () => {
    try {
      const version = versioned ? versioned[1] : VERSION;
      const path = navigation ? 'index.html' : versioned ? versioned[2] : relative;
      const name = PREFIX + version;
      // Migration only: older pages ask for unversioned lazy assets. Keep their
      // latest legacy shell available; new pages request immutable release URLs.
      if (!versioned && !navigation && event.clientId) {
        const metadata = await caches.open(CLIENTS);
        const record = await metadata.match(new URL('__pwa__/clients/' + event.clientId, SCOPE).href);
        if (!record) {
          const legacy = (await caches.keys()).filter(key => isGeneration(key) && !isVersion(key.slice(PREFIX.length))).at(-1);
          if (legacy) {
            const old = await (await caches.open(legacy)).match(new URL(path, SCOPE).href);
            if (old) return old;
          }
        }
      }
      if (!(await caches.has(name))) return fetch(request);
      const cache = await caches.open(name);
      const marker = await cache.match(markerUrl(version));
      const manifest = marker ? (await marker.json()).assets : version === VERSION ? MANIFEST : null;
      if (!manifest || !Object.hasOwn(manifest, path)) return fetch(request);
      const cached = marker && await cache.match(releaseUrl(version, path));
      if (cached) return cached;
      // Eviction recovery is network-only and integrity checked. No runtime put.
      const recovered = await verified(await fetch(releaseUrl(version, path), {cache: 'no-store'}), manifest[path]);
      if (!recovered) throw new Error('Release asset missing or changed: ' + path);
      return recovered;
    } catch (error) {
      await report('Offline shell asset unavailable: ' + error);
      throw error;
    }
  })());
});
