#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

function assert(condition, message) {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
}

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
const expected = [
  "GTA6Countdown/Shared/News/NewsArticle.swift",
  "GTA6Countdown/Shared/News/Credibility.swift",
  "GTA6Countdown/Shared/News/NewsPayload.swift",
  "GTA6Countdown/Shared/Config/RemoteConfig.swift",
  "GTA6Countdown/Shared/Storage/SharedCache.swift",
];

for (const relativePath of expected) {
  assert(fs.existsSync(path.join(root, relativePath)), `missing ${relativePath}`);
}

const fixture = JSON.parse(fs.readFileSync(path.join(root, "Fixtures/news-payload.json"), "utf8"));
assert(fixture.schemaVersion === 1, "fixture schemaVersion must be 1");
assert(Array.isArray(fixture.articles) && fixture.articles.length === 2, "fixture must contain articles");

const credibility = fs.readFileSync(path.join(root, expected[1]), "utf8");
for (const value of ["official", "media", "unverified"]) {
  assert(credibility.includes(`case ${value}`), `missing credibility ${value}`);
}
assert(!credibility.includes("case rumor"), "rumor must not be an accepted credibility value");

const config = fs.readFileSync(path.join(root, expected[3]), "utf8");
assert(config.includes('defaultReleaseDate = "2026-11-19"'), "remote config must preserve approved fallback date");

const cache = fs.readFileSync(path.join(root, expected[4]), "utf8");
assert(cache.includes("appGroupContainerURL"), "App Group lookup must be injectable");
assert(cache.includes("sandboxDirectoryURL"), "sandbox fallback must be injectable");
assert(cache.includes("invalidFilename"), "unsafe cache filenames must be rejected");
assert(cache.includes("dataWriter"), "cache writer must be injectable for failure testing");
assert(
  cache.indexOf("defer { try? fileManager.removeItem(at: temporaryURL) }") < cache.indexOf("try dataWriter(data, temporaryURL)"),
  "temporary cleanup must be installed before the write begins",
);
assert(cache.includes("replaceItemAt"), "existing cache must use atomic replacement");
assert(cache.includes("moveItem"), "first cache write must atomically move a temporary file");

console.log("PASS: news decoding and shared cache source contracts are complete");
