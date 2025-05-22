// CORS Proxy for local development
window.createCorsProxy = function () {
  // Log initialization
  console.log("Setting up CORS proxy for Flutter web");

  // Keep track of proxied endpoints
  const proxiedApis = ["api.flutterflow.io"];

  // Proxy setup for fetch API
  const originalFetch = window.fetch;
  window.fetch = function (url, options = {}) {
    let urlString = url;
    if (url instanceof Request) {
      urlString = url.url;
    }

    // Check if this is an API that needs proxying
    const needsProxy = proxiedApis.some((api) => urlString.includes(api));

    if (needsProxy && window.location.hostname === "localhost") {
      console.log("🔄 Proxying fetch request:", urlString);

      // Use CORS Anywhere as a fallback proxy service
      const proxyUrl = "https://cors-anywhere.herokuapp.com/" + urlString;
      console.log("↪️ Redirecting to proxy:", proxyUrl);

      // If the original request was a Request object
      if (url instanceof Request) {
        const originalRequest = url;
        const newRequest = new Request(proxyUrl, {
          method: originalRequest.method,
          headers: originalRequest.headers,
          body: originalRequest.body,
          mode: "cors",
          credentials: originalRequest.credentials,
          cache: originalRequest.cache,
          redirect: originalRequest.redirect,
          referrer: originalRequest.referrer,
          integrity: originalRequest.integrity,
        });
        return originalFetch(newRequest);
      }

      // If it was a string URL
      return originalFetch(proxyUrl, options);
    }

    // Otherwise use normal fetch
    return originalFetch(url, options);
  };

  // Also intercept XMLHttpRequest
  const originalXhrOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    // Check if this is an API that needs proxying
    const needsProxy = proxiedApis.some((api) => url.includes(api));

    if (needsProxy && window.location.hostname === "localhost") {
      console.log("🔄 Proxying XHR request:", url);

      // Use CORS Anywhere as a fallback proxy
      const proxyUrl = "https://cors-anywhere.herokuapp.com/" + url;
      console.log("↪️ Redirecting XHR to proxy:", proxyUrl);

      return originalXhrOpen.call(this, method, proxyUrl, ...rest);
    }

    return originalXhrOpen.call(this, method, url, ...rest);
  };

  console.log("✅ CORS proxy initialized for local development");
};
