#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const exists = (relative) => fs.existsSync(path.join(root, relative));
const assert = (condition, message) => {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
};

for (const file of [
  "GTA6CountdownWidgets/GTA6CountdownWidgets.swift",
  "GTA6CountdownWidgets/CountdownWidget.swift",
  "GTA6CountdownWidgets/NewsWidget.swift",
  "GTA6CountdownWidgets/WidgetDataProvider.swift",
  "GTA6CountdownTests/WidgetTimelineTests.swift",
]) assert(exists(file), `missing ${file}`);

const bundle = read("GTA6CountdownWidgets/GTA6CountdownWidgets.swift");
const countdown = read("GTA6CountdownWidgets/CountdownWidget.swift");
const news = read("GTA6CountdownWidgets/NewsWidget.swift");
const provider = read("GTA6CountdownWidgets/WidgetDataProvider.swift");
const coverPipeline = read("GTA6Countdown/Shared/Widgets/WidgetCoverPipeline.swift");
const repository = read("GTA6Countdown/Services/NewsRepository.swift");
const project = read("project.yml");

assert(/@main\s+struct\s+GTA6CountdownWidgets\s*:\s*WidgetBundle/.test(bundle), "entry point must be a WidgetBundle");
assert((countdown.match(/StaticConfiguration\s*\(/g) || []).length === 1, "countdown must use StaticConfiguration");
assert((news.match(/StaticConfiguration\s*\(/g) || []).length === 1, "news must use StaticConfiguration");
assert(!/AppIntent|AppIntentConfiguration/.test(bundle + countdown + news + provider), "iOS 17 AppIntent APIs are forbidden");
assert(!/AsyncImage/.test(news), "widgets must receive provider-loaded cover data instead of AsyncImage");
assert(/\.supportedFamilies\s*\(\s*\[\s*\.systemSmall\s*,\s*\.systemMedium\s*\]/s.test(countdown), "countdown families must be small and medium");
assert(/\.supportedFamilies\s*\(\s*\[\s*\.systemMedium\s*,\s*\.systemLarge\s*\]/s.test(news), "news families must be medium and large");
assert(/WidgetKinds\.news/.test(repository) && /reloadTimelines\s*\(\s*ofKind:/.test(repository), "repository must reload only the news widget kind");
assert(/WidgetKinds\.countdown/.test(countdown) && /WidgetKinds\.news/.test(news), "widget kinds must be centralized");
assert(/SharedCache/.test(provider) && /NewsAPIClient/.test(provider), "provider must support cache and network fallback");
assert(/WidgetCoverPipeline/.test(provider) && /timeoutIntervalForRequest/.test(provider), "provider must safely prefetch covers with a short timeout");
assert(/HTTPURLResponse/.test(coverPipeline) && /allowedMIMETypes/.test(coverPipeline), "cover responses must validate status and MIME");
assert(/URLSessionDataDelegate/.test(coverPipeline) && /didReceive data/.test(coverPipeline), "cover transport must enforce its limit while streaming");
assert(/deadlineNanoseconds/.test(coverPipeline) && /cancelAll/.test(coverPipeline), "cover pipeline must enforce an overall deadline");
assert(/maximumSourceResponseSize/.test(coverPipeline) && /maximumEntryImageSize/.test(coverPipeline), "cover source and entry sizes must be bounded");
assert(/CGImageSourceCreateThumbnailAtIndex/.test(coverPipeline), "covers must be downsampled before entering a timeline");
assert(/nextRefresh/.test(provider) && /policy:\s*\.after\(plan\.nextRefresh\)/s.test(provider), "countdown timeline must refresh at the next local midnight");
assert(/sizeCategory/.test(countdown) && /sizeCategory/.test(news), "widgets must adapt to Dynamic Type categories");
assert(/widgetURL/.test(news) && /WidgetNewsRoute/.test(news), "news widgets must expose article deep links");
assert(/com\.apple\.security\.application-groups/.test(project), "project must declare App Group entitlements");
assert(/GTA6Countdown\/Shared/.test(project), "widget target must compile the Foundation-only shared layer");
assert(/GTA6Countdown\/Services\/NewsAPIClient\.swift/.test(project), "widget target must compile the API client without App UI sources");

console.log("PASS: Task 9 WidgetKit source contract is valid");
