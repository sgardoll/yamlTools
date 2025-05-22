// This service worker doesn't do anything by default, but we can use it
// to handle CORS requests if needed in the future.
// For now, just register it to ensure we have control over network requests.

self.addEventListener("install", (event) => {
  console.log("YAML Tools Service Worker installed");
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  console.log("YAML Tools Service Worker activated");
  return self.clients.claim();
});

// We'll leave fetch events unhandled for now, as we're using a client-side proxy
// But this is where we could intercept and modify network requests in the future
