(() => {
  // Modern Flutter initialization pattern with proper timing
  const RESOURCES = {};

  // Function to initialize Flutter when loader is available
  function initializeFlutter() {
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
      return true;
    }
    return false;
  }

  // Register service worker first
  if ("serviceWorker" in navigator) {
    window.addEventListener("flutter-first-frame", function () {
      navigator.serviceWorker.register("flutter_service_worker.js");
    });
  }

  // Try to initialize immediately if Flutter is already available
  if (!initializeFlutter()) {
    // If Flutter loader isn't available yet, wait for it
    window.addEventListener("load", function () {
      // Try again after window load
      if (!initializeFlutter()) {
        // Last resort: poll for Flutter loader
        let attempts = 0;
        const maxAttempts = 50; // 5 seconds maximum
        const pollInterval = setInterval(() => {
          attempts++;
          if (initializeFlutter() || attempts >= maxAttempts) {
            clearInterval(pollInterval);
            if (attempts >= maxAttempts) {
              console.error("Flutter loader not found after waiting");
            }
          }
        }, 100);
      }
    });
  }
})();
