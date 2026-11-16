"use strict";
// The demo has no server: API reads come from the JSON files build.py wrote next to the page,
// and thread actions answer with a notice instead of changing anything.
(function () {
  const realFetch = window.fetch.bind(window);
  const base = new URL(".", document.baseURI);
  function json(status, body) {
    return new Response(JSON.stringify(body), {status, headers: {"Content-Type": "application/json"}});
  }
  window.fetch = function (input, init) {
    const url = new URL(typeof input === "string" ? input : input.url, location.href);
    if (url.origin !== location.origin || !url.pathname.startsWith("/api/")) return realFetch(input, init);
    if ((init && init.method || "GET").toUpperCase() !== "GET") {
      return Promise.resolve(json(200, {ok: false, error: "demo",
        message: "This is a demo with made-up data, so actions do nothing."}));
    }
    const route = url.pathname.slice("/api/".length);
    const file = /^dreams\/\d{4}-\d{2}-\d{2}$/.test(route) ? route + ".json" :
      ["lately", "stats", "progress", "threads", "dreams"].includes(route) ? route + ".json" : null;
    if (!file) return Promise.resolve(json(404, {ok: false, error: "not_found"}));
    return realFetch(new URL("api/" + file, base));
  };
})();
