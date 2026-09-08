// Loads the app from files it ships with, never from the network.
//
// Flutter's default is to fetch its rendering engine from
// www.gstatic.com at startup. That makes an application which is otherwise
// entirely local — the database is bundled, edits stay in the browser, nothing
// is ever uploaded — refuse to start on a machine with no internet, behind a
// proxy, or on a locked-down institutional network. A researcher opening this
// on a train should not see a blank screen.
//
// `canvasKitBaseUrl` points at the copy Flutter already places next to the
// built app, so the engine comes from the same origin as everything else.
// This file replaces the generated bootstrap; the two placeholders below are
// filled in at build time and must stay.
{{flutter_js}}
{{flutter_build_config}}

// Registered by hand, and pointedly not through the loader's
// `serviceWorkerSettings`: that installs the worker Flutter generates, which
// in this version unregisters itself and caches nothing. See web/sw.js.
//
// Registered immediately rather than on window load, which is the difference
// between the app working offline after one visit and after two. The engine,
// the fonts and the 9 MB database are all fetched during the first load; a
// worker registered at the end of it controls none of them, and a reader who
// installs the app and then loses the network gets nothing. Registering here
// costs one small script fetch before the engine starts.
// The browser's offer to install, held for the app to make in its own words.
//
// `beforeinstallprompt` fires once, early, and cannot be requested again, so
// this has to be listening before the engine starts. preventDefault() stops
// Chrome's own mini-infobar so the invitation appears in one place — the
// app's menu — rather than two.
window.pwaInstallEvent = null;
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  window.pwaInstallEvent = event;
});
window.addEventListener("appinstalled", () => {
  window.pwaInstallEvent = null;
});
window.pwaInstallAvailable = () => window.pwaInstallEvent !== null;
window.pwaInstallShow = async () => {
  const event = window.pwaInstallEvent;
  if (!event) return;
  // Spent either way: the browser will not replay a prompt that has been
  // shown, so holding on to it would leave a menu item that does nothing.
  window.pwaInstallEvent = null;
  event.prompt();
  await event.userChoice;
};

if ("serviceWorker" in navigator) {
  // Relative, so it resolves against <base href> and takes the scope of
  // whatever path the app is served from — "/" locally, "/MedievalDatabase/"
  // on project Pages.
  navigator.serviceWorker.register("sw.js").catch((e) => {
    // Not fatal. Without it the app still runs; it just needs the network.
    console.warn("Offline support unavailable:", e);
  });

  // Once everything is down, tell the worker what came down. The browser has
  // been keeping the list all along.
  window.addEventListener("load", () => {
    navigator.serviceWorker.ready.then((registration) => {
      const urls = performance
        .getEntriesByType("resource")
        .map((entry) => entry.name)
        .filter(
          (url) =>
            url.startsWith(location.origin) &&
            !url.endsWith("/version.json") &&
            !url.endsWith("/sw.js"),
        );
      registration.active?.postMessage({ type: "warm", urls });
    });
  });
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    // The engine also fetches a fallback typeface — one Roboto woff2 — from
    // fonts.gstatic.com at startup, and further Noto faces on demand for
    // glyphs the app's own fonts do not cover. Pointing this at a folder we
    // ship makes the first one local; the rest simply do not resolve, which
    // offline is the same outcome as not asking.
    fontFallbackBaseUrl: "fallback-fonts/",
  },
});
