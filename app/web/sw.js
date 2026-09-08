// Makes the app work with no network, and installable because of it.
//
// Flutter used to generate a caching service worker and no longer does — the
// one it writes now unregisters itself and nothing else, so this is ours.
//
// Everything the app needs is already same-origin: the engine, the fonts, the
// 9 MB database. There is nothing here that reaches another host, so caching
// the origin is enough to make the whole application work on a train.
//
// The cache is named from `version.json`, which Flutter generates from the
// `version:` line in pubspec.yaml. That ties four things to one number: what
// the navigation rail shows, what a release is tagged, what the cache is
// called, and therefore when a reader stops seeing the old build. **Bump the
// version in pubspec.yaml when you deploy.** Forgetting is not fatal — see
// the revalidation below — but bumping is what makes the changeover clean.
'use strict';

const PREFIX = 'price-explorer-';

let pending;

/// The cache this build should be using.
///
/// Resolved once per service worker start rather than per request: the worker
/// is killed whenever it goes idle, so this settles again soon enough after a
/// deploy without asking the network on every fetch.
function currentCache() {
  return (pending ??= resolveCacheName());
}

async function resolveCacheName() {
  try {
    // no-store, or the browser's own cache answers with the version we are
    // trying to detect a change away from.
    const response = await fetch('version.json', { cache: 'no-store' });
    if (response.ok) {
      const build = await response.json();
      const name = `${PREFIX}${build.version}+${build.build_number}`;
      // Anything under an older name is this app's, and superseded. Dropping
      // it here rather than in `activate` is deliberate: a deploy does not
      // change this file, so no new worker installs and `activate` never runs
      // again.
      for (const key of await caches.keys()) {
        if (key.startsWith(PREFIX) && key !== name) await caches.delete(key);
      }
      return name;
    }
  } catch (_) {
    // Offline. Fall through to whatever is already here.
  }
  const existing = (await caches.keys()).filter((k) => k.startsWith(PREFIX));
  return existing[0] ?? `${PREFIX}unknown`;
}

self.addEventListener('install', (event) => {
  // Only the page itself is precached here, and only because a navigation
  // that finds nothing cached fails before any of the rest could help. There
  // is no list of engine and asset files: those names come out of a Flutter
  // build, a hand-kept copy of them goes stale silently, and which renderer
  // is fetched depends on the browser. The page reports what it actually
  // loaded instead — see the 'warm' message below.
  event.waitUntil((async () => {
    const cache = await caches.open(await currentCache());
    await cache.add('index.html').catch(() => {});
  })());
  self.skipWaiting();
});

// What the first visit downloaded, as the page saw it.
//
// The engine, the renderer and the main bundle are all requested before this
// worker can possibly be controlling anything, so they are invisible to
// `fetch` on a first visit — which is the difference between the app working
// offline after one visit and after two. The page hands over its own resource
// timings once it has finished loading, so what gets stored is exactly what
// this browser really used: the right CanvasKit build for it, and nothing
// downloaded twice to cover a browser the reader does not have.
self.addEventListener('message', (event) => {
  if (event.data?.type !== 'warm') return;
  event.waitUntil((async () => {
    const cache = await caches.open(await currentCache());
    await Promise.all(event.data.urls.map(async (url) => {
      // Already held: leave it. Re-fetching would download the database again
      // on every load.
      if (await cache.match(url)) return;
      try {
        const response = await fetch(url, { cache: 'no-cache' });
        if (response.ok && response.status === 200) await cache.put(url, response);
      } catch (_) {
        // One file that will not come is not worth failing the rest over.
      }
    }));
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // version.json is how a new build is noticed, so it is never served from
  // the cache.
  if (url.pathname.endsWith('/version.json')) return;

  // The page itself comes from the network when there is one, so a deploy is
  // picked up on the next load rather than the one after.
  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request));
    return;
  }

  event.respondWith(staleWhileRevalidate(request));
});

async function networkFirst(request) {
  const cache = await caches.open(await currentCache());
  try {
    const response = await fetch(request);
    if (response.ok) cache.put(request, response.clone());
    return response;
  } catch (_) {
    return (await cache.match(request)) ??
        (await cache.match('index.html')) ??
        Response.error();
  }
}

/// Answer from the cache at once, and quietly refresh it for next time.
///
/// Cache-first alone would pin a reader to an old build for as long as they
/// never clear their browser, which is forever; network-first would make
/// every load wait on 25 MB of engine, database and fonts even though none of
/// it changed. This costs one stale load after a deploy and then corrects
/// itself, which is the right trade when a version bump avoids even that.
async function staleWhileRevalidate(request) {
  const cache = await caches.open(await currentCache());
  const hit = await cache.match(request);

  const fresh = fetch(request)
      .then((response) => {
        // Partial and redirected responses are not sound to replay later.
        if (response.ok && response.status === 200 && !response.redirected) {
          cache.put(request, response.clone());
        }
        return response;
      })
      .catch(() => undefined);

  return hit ?? (await fresh) ?? Response.error();
}
