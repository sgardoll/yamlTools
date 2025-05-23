(() => {
  const serviceWorkerVersion = null;
  const RESOURCES = {};

  // The application's service worker version.
  // This is used to determine when the worker has been updated.
  const APPLICATION_CACHE_VERSION = "1";

  // Flutter service worker registration
  if ("serviceWorker" in navigator) {
    window.addEventListener("flutter-first-frame", function () {
      navigator.serviceWorker.register(
        "flutter_service_worker.js?v=" + serviceWorkerVersion
      );
    });
  }

  // Initialize the Flutter app
  if (typeof _flutter !== "undefined" && _flutter.loader) {
    _flutter.loader.loadEntrypoint({
      serviceWorker: {
        serviceWorkerVersion: serviceWorkerVersion,
      },
      onEntrypointLoaded: function (engineInitializer) {
        engineInitializer.initializeEngine().then(function (appRunner) {
          appRunner.runApp();
        });
      },
    });
  } else {
    // Fallback for older Flutter versions
    window.addEventListener("load", function (ev) {
      // Download main.dart.js
      _flutter.loader.loadEntrypoint({
        serviceWorker: {
          serviceWorkerVersion: serviceWorkerVersion,
        },
      });
    });
  }
})();
