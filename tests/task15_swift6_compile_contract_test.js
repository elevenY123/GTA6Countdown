#!/usr/bin/env node

const fs = require("node:fs");
const assert = require("node:assert/strict");

const read = (path) => fs.readFileSync(path, "utf8");
const homeView = read("GTA6Countdown/Features/Home/HomeView.swift");
const homeModel = read("GTA6Countdown/Features/Home/HomeViewModel.swift");
const mapView = read("GTA6Countdown/Features/Map/MapView.swift");
const mapModel = read("GTA6Countdown/Features/Map/MapViewModel.swift");
const mapWebView = read("GTA6Countdown/Features/Map/MapWebView.swift");
const newsView = read("GTA6Countdown/Features/News/NewsListView.swift");

assert.doesNotMatch(homeView, /=\s*HomeViewModel\(\)/,
  "HomeView must not instantiate a main-actor model in a default argument");
assert.doesNotMatch(mapView, /=\s*MapViewModel\(\)/,
  "MapView must not instantiate a main-actor model in a default argument");
assert.doesNotMatch(newsView, /=\s*NewsViewModel\(\)/,
  "NewsListView must not instantiate a main-actor model in a default argument");
assert.doesNotMatch(homeModel, /ticker:.*=\s*SystemCountdownTicker\(\)/,
  "HomeViewModel must construct actor-isolated dependencies inside its convenience initializer");
assert.doesNotMatch(mapModel, /opener:.*=\s*SystemMapExternalOpener\(\)/,
  "MapViewModel must construct its system opener inside its convenience initializer");

for (const method of ["navigateBack", "navigateForward", "reloadContent"]) {
  assert.match(mapModel, new RegExp(`func ${method}\\(\\)`),
    `MapWebControlling must declare ${method}`);
  assert.match(mapWebView, new RegExp(`func ${method}\\(\\)`),
    `WKWebView must provide the ${method} adapter`);
}

console.log("PASS: Swift 6 actor isolation and WKWebView adapter contracts are present");
