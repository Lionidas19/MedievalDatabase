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
