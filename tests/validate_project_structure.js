#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function scalar(value) {
  const trimmed = value.trim();
  if (trimmed === "{}") return {};
  if (trimmed === "[]") return [];
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (/^".*"$/.test(trimmed)) return JSON.parse(trimmed);
  if (/^\[.*\]$/.test(trimmed)) {
    const body = trimmed.slice(1, -1).trim();
    return body ? body.split(",").map((item) => scalar(item)) : [];
  }
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);
  return trimmed;
}

function parseYAML(source) {
  const lines = source
    .split(/\r?\n/)
    .map((raw, index) => ({ raw, index: index + 1 }))
    .filter(({ raw }) => raw.trim() && !raw.trimStart().startsWith("#"))
    .map(({ raw, index }) => ({
      indent: raw.length - raw.trimStart().length,
      text: raw.trim(),
      index,
    }));

  function keyValue(text, line) {
    const match = /^([^:]+):(.*)$/.exec(text);
    if (!match) fail(`invalid YAML mapping on line ${line}`);
    return [match[1].trim(), match[2].trim()];
  }

  function block(start, indent) {
    if (start >= lines.length || lines[start].indent < indent) return [{}, start];
    const isArray = lines[start].indent === indent && lines[start].text.startsWith("-");
    const result = isArray ? [] : {};
    let cursor = start;

    while (cursor < lines.length && lines[cursor].indent === indent) {
      const line = lines[cursor];
      if (isArray) {
        if (!line.text.startsWith("-")) fail(`mixed YAML collection on line ${line.index}`);
        const remainder = line.text.slice(1).trim();
        if (!remainder) {
          const [child, next] = block(cursor + 1, lines[cursor + 1]?.indent ?? indent + 2);
          result.push(child);
          cursor = next;
          continue;
        }
        if (remainder.includes(":")) {
          const [key, value] = keyValue(remainder, line.index);
          const item = { [key]: value ? scalar(value) : {} };
          cursor += 1;
          if (cursor < lines.length && lines[cursor].indent > indent) {
            const [extra, next] = block(cursor, lines[cursor].indent);
            Object.assign(item, extra);
            cursor = next;
          }
          result.push(item);
          continue;
        }
        result.push(scalar(remainder));
        cursor += 1;
        continue;
      }

      if (line.text.startsWith("-")) fail(`mixed YAML collection on line ${line.index}`);
      const [key, value] = keyValue(line.text, line.index);
      cursor += 1;
      if (value) {
        result[key] = scalar(value);
      } else if (cursor < lines.length && lines[cursor].indent > indent) {
        const [child, next] = block(cursor, lines[cursor].indent);
        result[key] = child;
        cursor = next;
      } else {
        result[key] = {};
      }
    }
    return [result, cursor];
  }

  const [document, cursor] = block(0, lines[0]?.indent ?? 0);
  if (cursor !== lines.length) fail(`unsupported YAML indentation on line ${lines[cursor].index}`);
  return document;
}

function assert(condition, message) {
  if (!condition) fail(message);
}

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
const projectPath = path.join(root, "project.yml");
assert(fs.existsSync(projectPath), "missing project.yml");

const project = parseYAML(fs.readFileSync(projectPath, "utf8"));
assert(project.options?.deploymentTarget?.iOS === "16.0", "deployment target must be iOS 16.0");

const expectedTargets = {
  GTA6Countdown: { type: "application", source: "GTA6Countdown" },
  GTA6CountdownWidget: { type: "app-extension", source: "GTA6CountdownWidgets" },
  GTA6CountdownTests: { type: "bundle.unit-test", source: "GTA6CountdownTests" },
};

for (const [name, expected] of Object.entries(expectedTargets)) {
  const target = project.targets?.[name];
  assert(target, `missing target ${name}`);
  assert(target.type === expected.type, `${name} must have type ${expected.type}`);
  assert(target.platform === "iOS", `${name} must target iOS`);
  const sources = (target.sources || []).map((source) =>
    typeof source === "string" ? source : source.path
  );
  assert(sources.includes(expected.source), `${name} must source ${expected.source}`);
  assert(fs.statSync(path.join(root, expected.source), { throwIfNoEntry: false })?.isDirectory(),
    `missing source directory ${expected.source}`);
}

const widgetSwiftFiles = fs.readdirSync(path.join(root, "GTA6CountdownWidgets"))
  .filter((file) => file.endsWith(".swift"));
const widgetMainCount = widgetSwiftFiles.reduce((count, file) => {
  const source = fs.readFileSync(path.join(root, "GTA6CountdownWidgets", file), "utf8");
  return count + (source.match(/@main\b/g) || []).length;
}, 0);
assert(widgetMainCount === 1, "widget extension must define exactly one @main entry");

const appDependencies = project.targets.GTA6Countdown.dependencies || [];
assert(appDependencies.some((dependency) =>
  dependency.target === "GTA6CountdownWidget" && dependency.embed === true
), "app must embed GTA6CountdownWidget");

const testTargets = project.schemes?.GTA6Countdown?.test?.targets || [];
assert(testTargets.some((target) =>
  target === "GTA6CountdownTests" || target?.name === "GTA6CountdownTests"
), "GTA6Countdown scheme must run GTA6CountdownTests");

const rootTabPath = path.join(root, "GTA6Countdown/App/RootTabView.swift");
assert(fs.existsSync(rootTabPath), "missing RootTabView.swift");
const rootTabSource = fs.readFileSync(rootTabPath, "utf8");
const enumMatch = /enum\s+RootTab\s*:\s*String\s*,\s*CaseIterable\s*\{([\s\S]*?)\n\}/.exec(rootTabSource);
assert(enumMatch, "RootTab must be a String, CaseIterable enum");
const identifiers = [...enumMatch[1].matchAll(/\bcase\s+(\w+)(?:\s*=\s*"([^"]+)")?/g)]
  .map((match) => match[2] || match[1]);
assert(JSON.stringify(identifiers) === JSON.stringify(["home", "news", "map"]),
  "RootTab stable IDs must be exactly home, news, map");

console.log("PASS: parsed iOS project structure is valid");
