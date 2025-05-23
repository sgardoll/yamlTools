(() => {
  // Modern Flutter initialization pattern
  const RESOURCES = {};

  // Flutter service worker registration
  if ("serviceWorker" in navigator) {
    window.addEventListener("flutter-first-frame", function () {
      navigator.serviceWorker.register("flutter_service_worker.js");
    });
  }

  // Initialize the Flutter app using modern API
  if (typeof _flutter !== "undefined" && _flutter.loader) {
    _flutter.loader.load({
      serviceWorkerSettings: {
        serviceWorkerVersion: null,
      },
      onEntrypointLoaded: function (engineInitializer) {
        engineInitializer.initializeEngine().then(function (appRunner) {
          appRunner.runApp();
        });
      },
    });
  } else {
    // Fallback for older Flutter versions or if _flutter is not available
    window.addEventListener("load", function (ev) {
      console.warn(
        "Flutter loader not found, attempting fallback initialization"
      );
      if (typeof _flutter !== "undefined" && _flutter.loader) {
        _flutter.loader.load({
          serviceWorkerSettings: {
            serviceWorkerVersion: null,
          },
        });
      }
    });
  }
})();
