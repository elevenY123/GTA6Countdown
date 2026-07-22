#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const files = [
  "GTA6Countdown/Features/Map/MapView.swift",
  "GTA6Countdown/Features/Map/MapWebView.swift",
  "GTA6Countdown/Features/Map/MapViewModel.swift",
  "GTA6CountdownTests/MapNavigationTests.swift",
];

for (const relative of files) {
  if (!fs.existsSync(path.join(root, relative))) {
    console.error(`FAIL: missing ${relative}`);
    process.exit(1);
  }
}

const sources = files.map(file => fs.readFileSync(path.join(root, file), "utf8")).join("\n");
const productionSources = files.slice(0, 3)
  .map(file => fs.readFileSync(path.join(root, file), "utf8"))
  .join("\n");
const rootTab = fs.readFileSync(path.join(root, "GTA6Countdown/App/RootTabView.swift"), "utf8");
const checks = [
  [sources.includes("https://map.mygta.online/gta6-map"), "exact initial map URL is required"],
  [sources.includes("WKWebView"), "map must use WKWebView"],
  [sources.includes("WKNavigationDelegate"), "map navigation must be delegated safely"],
  [sources.includes("社区预测地图"), "native community-map title is required"],
  [sources.includes("并非 Rockstar 官方最终地图"), "non-official warning is required"],
  [sources.includes("MyGTA 中文社区"), "visible attribution is required"],
  [sources.includes("打开 Safari"), "Safari fallback is required"],
  [sources.includes("canGoBack") && sources.includes("canGoForward"), "back/forward state is required"],
  [sources.includes("retry") && sources.includes("errorMessage"), "recoverable error state is required"],
  [productionSources.includes("NSKeyValueObservation"), "web history state must be observed with KVO"],
  [productionSources.includes("dismantleUIView"), "WebView teardown must invalidate navigation observation"],
  [productionSources.includes("webViewWebContentProcessDidTerminate"), "web content termination must be recoverable"],
  [productionSources.includes("url.port") || productionSources.includes("effectivePort"), "same-origin policy must validate ports"],
  [productionSources.includes("allowsHitTesting(viewModel.errorMessage == nil)"), "failed WebView must not remain interactive behind its error"],
  [productionSources.includes("accessibilityHidden(viewModel.errorMessage != nil)"), "failed WebView must be hidden from accessibility"],
  [productionSources.includes("didCommitNavigation") && productionSources.includes("currentURL"), "browser fallback must track the committed internal URL"],
  [sources.includes("MapExternalOpening"), "external opener must be injectable"],
  [productionSources.includes("MapNavigationDeciding"), "navigation policy must be injectable"],
  [sources.includes("MapNavigationPolicy"), "navigation policy must be independently testable"],
  [!sources.includes("evaluateJavaScript"), "script injection is forbidden"],
  [!sources.includes("WKUserScript"), "content-altering user scripts are forbidden"],
  [rootTab.includes("MapView()"), "map tab must render MapView"],
];

for (const [condition, message] of checks) {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
}
console.log("PASS: Task 8 attributed community map contracts are present");
