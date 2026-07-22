const assert = require("node:assert/strict");
const fs = require("node:fs");

const home = fs.readFileSync("GTA6Countdown/Features/Home/HomeView.swift", "utf8");
const placeholder = fs.readFileSync("GTA6Countdown/Features/News/NewsCoverPlaceholder.swift", "utf8");
const about = fs.existsSync("GTA6Countdown/Features/About/AboutView.swift")
  ? fs.readFileSync("GTA6Countdown/Features/About/AboutView.swift", "utf8")
  : "";
const project = fs.readFileSync("project.yml", "utf8");
const validator = fs.readFileSync("scripts/validate-assets.sh", "utf8");

assert.match(home, /@Environment\(\\\.colorScheme\)/, "Home must respond to light/dark appearance");
assert.match(home, /HeroLight/, "Home must use the light hero asset");
assert.match(home, /HeroDark/, "Home must use the dark hero asset");
assert.match(home, /info\.circle/, "Home must expose the About entry");
assert.match(home, /AboutView\(/, "Home must present AboutView");
assert.match(home, /colors:\s*\[\.black\.opacity\(0\.(?:3\d|[4-9]\d)\),\s*\.black\.opacity\(0\.72\)\]/, "Hero top scrim must be at least 0.30 for white text contrast");
assert.match(placeholder, /NewsPlaceholder/, "News fallback must use the original placeholder asset");
assert.match(about, /非官方/, "About must clearly say the app is unofficial");
assert.match(about, /Rockstar Games/, "About must attribute Rockstar Games");
assert.match(about, /MyGTA/, "About must attribute the community map");
assert.match(about, /不收集.*设备标识/, "About must disclose that device identifiers are not collected");
assert.match(about, /浏览新闻列表.*直接.*来源站.*封面/, "About must disclose third-party cover requests during list browsing");
assert.match(about, /IP.*User-Agent/, "About must disclose routine network information shared with cover hosts");
assert.match(project, /ASSETCATALOG_COMPILER_APPICON_NAME:\s*AppIcon/, "The app target must compile the AppIcon set");
assert.doesNotMatch(validator, /declare\s+-A/, "Asset validation must support macOS Bash 3.2");
assert.match(validator, /sha256sum/, "Asset validation must support sha256sum");
assert.match(validator, /shasum\s+-a\s+256/, "Asset validation must fall back to macOS shasum");
assert.match(validator, /for dependency in rg identify awk cmp/, "Asset validation must enumerate required dependencies");
assert.match(validator, /command -v "\$dependency"/, "Asset validation must check every enumerated dependency");

console.log("task13 assets/about contract passed");
