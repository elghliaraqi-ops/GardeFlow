{{flutter_js}}
{{flutter_build_config}}

(async () => {
  const buildId = '__GARDEFLOW_BUILD_ID__';
  const resetMarker = `gardeflow-sw-reset-${buildId}`;
  let hadServiceWorkerController = false;

  try {
    if ('serviceWorker' in navigator) {
      hadServiceWorkerController = navigator.serviceWorker.controller != null;
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => registration.unregister()));
    }

    if ('caches' in window) {
      const cacheNames = await caches.keys();
      const flutterCacheNames = cacheNames.filter((name) =>
        name === 'flutter-app-cache' ||
        name === 'flutter-temp-cache' ||
        name === 'flutter-app-manifest' ||
        name.startsWith('flutter-app-') ||
        name.startsWith('flutter-temp-')
      );
      await Promise.all(flutterCacheNames.map((name) => caches.delete(name)));
    }
  } catch (error) {
    console.warn('GardeFlow: legacy web cache cleanup failed.', error);
  }

  // An already-controlled tab keeps using its previous service worker until it
  // navigates. Reload exactly once after unregistering so the next load is
  // guaranteed to be network-controlled rather than served by a stale worker.
  if (hadServiceWorkerController && sessionStorage.getItem(resetMarker) !== 'done') {
    sessionStorage.setItem(resetMarker, 'done');
    const refreshUrl = new URL(window.location.href);
    refreshUrl.searchParams.set('build', buildId);
    window.location.replace(refreshUrl.toString());
    return;
  }

  // GitHub Pages can cache static files. Give the compiled entry point the same
  // immutable build identifier as the bootstrap script so every deployment
  // requests the current main.dart.js instead of a previously cached copy.
  const builds = window._flutter?.buildConfig?.builds;
  if (Array.isArray(builds)) {
    for (const build of builds) {
      if (build && build.mainJsPath === 'main.dart.js') {
        build.mainJsPath = `main.dart.js?build=${buildId}`;
      }
    }
  }

  await _flutter.loader.load();
})();
