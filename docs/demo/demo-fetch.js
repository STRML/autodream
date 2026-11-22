"use strict";
(function () {
  const realFetch = window.fetch.bind(window);
  const base = new URL(".", document.baseURI);
  const DATE = /\b(\d{4})-(\d{2})-(\d{2})(?=\b|T)/g;
  function dayNumber(year, month, day) { return Date.UTC(year, month - 1, day) / 86400000; }
  function format(number) { return new Date(number * 86400000).toISOString().slice(0, 10); }
  const built = (window.DEMO_BUILT || "").split("-").map(Number);
  function currentShift() {
    const now = new Date();
    return built.length === 3 ?
      dayNumber(now.getFullYear(), now.getMonth() + 1, now.getDate()) - dayNumber(built[0], built[1], built[2]) : 0;
  }
  const shift = currentShift();
  function move(text, days) {
    return text.replace(DATE, function (_, y, m, d) { return format(dayNumber(+y, +m, +d) + days); });
  }
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
    const delta = currentShift() - shift;
    if (delta !== 0) {
      history.replaceState(null, "", move(location.hash, delta) || location.pathname);
      location.reload();
      return new Promise(function () {});
    }
    const route = move(decodeURIComponent(url.pathname.slice("/api/".length)), -shift);
    const file = /^dreams\/\d{4}-\d{2}-\d{2}$/.test(route) ? route + ".json" :
      ["lately", "stats", "progress", "threads", "dreams"].includes(route) ? route + ".json" : null;
    if (!file) return Promise.resolve(json(404, {ok: false, error: "not_found"}));
    return realFetch(new URL("api/" + file, base)).then(function (response) {
      if (!response.ok) return response;
      return response.text().then(function (text) {
        return new Response(move(text, shift), {status: 200, headers: {"Content-Type": "application/json"}});
      });
    });
  };
})();
