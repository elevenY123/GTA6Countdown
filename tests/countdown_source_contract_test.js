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
const sourceDirectory = path.join(root, "GTA6Countdown", "Shared", "Countdown");
const expectedFiles = ["CountdownState.swift", "CountdownCalculator.swift", "MilestoneMessage.swift"];

for (const filename of expectedFiles) {
  assert(fs.existsSync(path.join(sourceDirectory, filename)), `missing ${filename}`);
}

const calculator = fs.readFileSync(path.join(sourceDirectory, "CountdownCalculator.swift"), "utf8");
assert(/protocol\s+CountdownClock\b/.test(calculator), "countdown clock must be injectable");
assert(calculator.includes("deviceCalendar"), "production calendar must derive device settings explicitly");

const stateSource = fs.readFileSync(path.join(sourceDirectory, "CountdownState.swift"), "utf8");
assert(stateSource.includes("preciseDays"), "state must expose precise day components");
assert(stateSource.includes("calendarDaysRemaining"), "state must expose natural local days remaining");

const messageSource = fs.readFileSync(path.join(sourceDirectory, "MilestoneMessage.swift"), "utf8");
assert(messageSource.includes("calendarDaysRemaining"), "milestone copy must use natural local days");

console.log("PASS: countdown source wiring is complete");
