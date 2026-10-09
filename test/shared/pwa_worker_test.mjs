// Executable worker regression tests using only Node's built-in APIs.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {webcrypto} from 'node:crypto';
import vm from 'node:vm';
import {test} from 'node:test';
const scope = 'https://example.test/studio/';
const prefix = 'free-model-studio-';
const current = 'a'.repeat(64), previous = 'b'.repeat(64);
const digest = async value => Buffer.from(await webcrypto.subtle.digest('SHA-256', new TextEncoder().encode(value))).toString('hex');
class Cache {
  data = new Map();
  async match(key) { return this.data.get(typeof key === 'string' ? key : key.url)?.clone(); }
  async put(key, value) { this.data.set(typeof key === 'string' ? key : key.url, value.clone()); }
  async keys() { return [...this.data.keys()].map(url => ({url})); }
  async delete(key) { return this.data.delete(typeof key === 'string' ? key : key.url); }
}
async function harness({corrupt = false} = {}) {
  const body = 'verified current bytes';
  const manifest = {'main.dart.js': {bytes: body.length, sha256: await digest(body)}};
  const stores = new Map(), listeners = {}, reports = [], fetches = [];
  const caches = {
    async open(name) { if (!stores.has(name)) stores.set(name, new Cache()); return stores.get(name); },
    async keys() { return [...stores.keys()]; },
    async has(name) { return stores.has(name); },
    async delete(name) { return stores.delete(name); },
  };
  const context = {URL, Request, Response, Headers, AbortController, crypto: webcrypto, caches,
    fetch: async request => { fetches.push(typeof request === 'string' ? request : request.url); return new Response(corrupt ? 'broken' : body); },
    self: {registration: {scope}, addEventListener: (name, callback) => listeners[name] = callback,
      clients: {matchAll: async () => [{id: 'old', url: scope, postMessage: value => reports.push(value)}], claim: async () => {}}, skipWaiting: async () => {}},
  };
  vm.runInNewContext(readFileSync('web/service_worker.js', 'utf8').replaceAll('__BUILD_ID__', current)
    .replace('__PRECACHE_MANIFEST__', JSON.stringify(manifest)), context);
  async function request(path, clientId = '') {
    let result;
    listeners.fetch({request: {url: new URL(path, scope).href, method: 'GET', mode: 'cors', headers: new Headers()}, clientId,
      respondWith: value => result = value});
    return result;
  }
  return {caches, listeners, request, reports, fetches, manifest, body};
}

test('flat install hashes all bytes before completion; configuration is not intercepted', async () => {
  const h = await harness(); let done;
  h.listeners.install({waitUntil: value => done = value}); await done;
  assert.ok(h.fetches.every(url => url.includes('?build=' + current) && !url.includes('__releases')));
  assert.equal(await (await h.request('main.dart.js?build=' + current)).text(), h.body);
  assert.equal(await h.request('config/local.json'), undefined);
  assert.equal(await h.request('main.dart.js?token=private'), undefined);
  assert.equal(await h.request('main.dart.js?build=' + current + '&token=private'), undefined);
});

test('failed integrity leaves no incomplete cache', async () => {
  const h = await harness({corrupt: true}); let done;
  h.listeners.install({waitUntil: value => done = value});
  await assert.rejects(done, /integrity/);
  assert.equal(await h.caches.has(prefix + current), false);
});

test('old legacy URLs and unversioned lazy loads stay with the old client cache', async () => {
  const h = await harness();
  const cache = await h.caches.open(prefix + previous);
  const legacy = '__releases/' + previous + '/';
  await cache.put(new URL(legacy + 'release.json', scope).href, new Response(JSON.stringify({format: 2, assets: h.manifest})));
  await cache.put(new URL(legacy + 'main.dart.js', scope).href, new Response('old cached bytes'));
  const clients = await h.caches.open(prefix + 'clients-v2');
  await clients.put(new URL('__pwa__/clients/old', scope).href, new Response(previous));
  assert.equal(await (await h.request(legacy + 'main.dart.js', 'old')).text(), 'old cached bytes');
  assert.equal(await (await h.request('main.dart.js', 'old')).text(), 'old cached bytes');
  assert.equal(h.fetches.length, 0);
});

test('uncached old builds fail explicitly instead of mixing current assets', async () => {
  const h = await harness();
  await assert.rejects(h.request('__releases/' + previous + '/main.dart.js'), /Save your work and reload/);
  await assert.rejects(h.request('main.dart.js?build=' + previous), /Save your work and reload/);
  assert.equal(h.fetches.length, 0);
});

test('the new install reuses verified legacy bytes without a network download', async () => {
  const h = await harness(); const cache = await h.caches.open(prefix + previous);
  const legacy = '__releases/' + previous + '/';
  await cache.put(new URL(legacy + 'release.json', scope).href, new Response(JSON.stringify({format: 2, assets: h.manifest})));
  await cache.put(new URL(legacy + 'main.dart.js', scope).href, new Response(h.body));
  let done; h.listeners.install({waitUntil: value => done = value}); await done;
  assert.equal(h.fetches.length, 0);
  assert.equal(await (await h.request('main.dart.js?build=' + current)).text(), h.body);
});
