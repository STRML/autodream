"use strict";
// The demo has no server: API reads come from the JSON files build.py wrote next to the page,
// and thread actions answer with a notice instead of changing anything.
//
// Every date in the demo is relative to the day it was built (window.DEMO_BUILT). Answers are
// moved forward by the days between that and the visitor's local today, so "the last 7 days",
// thread ages and the age filter read the same on any day, in any timezone. Relative ages do
// not change, so neither do the statuses computed from them.
// The shift is fixed for the page's life, because links already drawn carry shifted dates. The
// first request after the local date changes reloads the page instead, which redraws them all.
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
    if (currentShift() !== shift) {
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
