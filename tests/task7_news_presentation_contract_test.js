#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const required = [
  "GTA6Countdown/Features/News/NewsListView.swift",
  "GTA6Countdown/Features/News/PinnedOfficialCard.swift",
  "GTA6Countdown/Features/News/NewsRow.swift",
  "GTA6Countdown/Features/News/NewsDetailView.swift",
  "GTA6Countdown/Features/News/CredibilityBadge.swift",
  "GTA6Countdown/Features/News/NewsViewModel.swift",
  "GTA6Countdown/Features/News/NewsCoverPlaceholder.swift",
];
const validatorPath = path.join(root, "GTA6Countdown/Shared/News/NewsPayloadValidator.swift");
if (!fs.existsSync(validatorPath)) {
  console.error("FAIL: missing reusable NewsPayloadValidator");
  process.exit(1);
}

for (const relative of required) {
  if (!fs.existsSync(path.join(root, relative))) {
    console.error(`FAIL: missing ${relative}`);
    process.exit(1);
  }
}

const all = required.map(relative => fs.readFileSync(path.join(root, relative), "utf8")).join("\n");
const assertions = [
  [all.includes("AsyncCoverImage"), "news UI must reuse AsyncCoverImage"],
  [all.includes("refreshable"), "news list must support pull to refresh"],
  [all.includes("阅读原文"), "detail must include original-link action"],
  [all.includes("SFSafariViewController"), "original links must open safely in Safari view"],
  [all.includes("pinnedOfficialArticleID"), "pin selection must use configured official ID"],
  [all.includes("nonblockingIssue"), "cached refresh failures must remain nonblocking"],
  [all.includes("root-screen-news"), "news root must expose a stable accessibility ID"],
  [all.includes("canonicalTopicKey"), "news rows must deduplicate canonical topics"],
  [all.includes("NewsCoverPlaceholder"), "news covers must use the designed Vice placeholder"],
  [all.includes("news-detail-summary"), "summary-only detail must expose a stable test contract"],
  [!all.includes("CoverImagePlaceholder(systemImage:"), "news must not use generic cover placeholders"],
  [all.includes("folding(options:") || all.includes("lowercased(with:"), "canonical topic keys must be normalized locale-stably"],
  [!all.includes("RelativeDateTimeFormatter()"), "row rendering must not allocate a formatter per item"],
  [fs.readFileSync(path.join(root, "GTA6Countdown/Services/NewsRepository.swift"), "utf8").includes("actor NewsPayloadCache"), "cache IO must use an actor adapter"],
  [fs.readFileSync(path.join(root, "GTA6Countdown/Services/NewsRepository.swift"), "utf8").includes("stateGeneration"), "late hydration needs a refresh-authority generation guard"],
  [fs.readFileSync(path.join(root, "project.yml"), "utf8").includes("gta6countdown"), "article deep-link scheme must be registered"],
];

const repositorySource = fs.readFileSync(path.join(root, "GTA6Countdown/Services/NewsRepository.swift"), "utf8");
const refreshTaskAppliesState = /let task = Task \{[\s\S]*?state = result[\s\S]*?return result[\s\S]*?\}/.test(repositorySource);
assertions.push([refreshTaskAppliesState, "shared refresh task must apply state before completing"]);

for (const [condition, message] of assertions) {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
}
console.log("PASS: Task 7 news presentation contracts are present");
