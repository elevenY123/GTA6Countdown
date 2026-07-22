#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const assert = (condition, message) => {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
};

const workflow = read(".github/workflows/build-and-test.yml");
assert(workflow.includes("workflow_dispatch:"), "workflow must support manual builds");
assert(workflow.includes("push:") && workflow.includes("pull_request:"),
  "workflow must run for push and pull requests");
assert(/push:\s*\n\s+branches:\s*\[main\]/.test(workflow),
  "push builds must be limited to main to avoid duplicate pull-request runs");
assert(workflow.includes("backend-and-contracts:") && workflow.includes("ios-build-test-package:"),
  "Linux contracts and macOS iOS jobs must be separate");
assert(workflow.includes("runs-on: macos-15"), "iOS job must use the supported macos-15 runner");
assert(workflow.includes("sudo xcode-select -s /Applications/Xcode_16.4.app/Contents/Developer"),
  "iOS job must explicitly select Xcode 16.4");
assert(workflow.includes("xcodebuild -version"), "iOS job must report the selected Xcode version");
assert(workflow.includes("DERIVED_DATA: /tmp/GTA6CountdownDerivedData"),
  "job-level DerivedData must use a context valid before runner allocation");
assert(!/env:\s*\n\s+DERIVED_DATA:\s*\$\{\{\s*runner\.temp/.test(workflow),
  "job-level env must not use the unavailable runner context");
assert(workflow.includes("CODE_SIGNING_ALLOWED=NO"), "device build must not require distribution signing");
assert(workflow.includes("scripts/package-ipa.sh") && workflow.includes("scripts/validate-ipa.sh"),
  "workflow must package and validate the IPA");
assert(workflow.includes("actions/upload-artifact@v4"), "workflow must upload the IPA artifact");

const packageScript = read("scripts/package-ipa.sh");
const widgetSigning = packageScript.indexOf('codesign "${widget_args[@]}" "$widget"');
const appSigning = packageScript.indexOf('codesign "${app_args[@]}" "$app"');
assert(widgetSigning >= 0 && appSigning > widgetSigning,
  "package script must ad-hoc sign the Widget before the main app");
assert(!/(p12|provisioning profile|APPLE_CERTIFICATE)/i.test(workflow + packageScript),
  "build must not depend on distribution credentials");

const readme = read("README.md");
const install = read("TROLLSTORE_INSTALL.md");
const debugConfig = read("Config/Debug.xcconfig");
const releaseConfig = read("Config/Release.xcconfig");
assert(readme.includes("API_BASE_URL") && readme.includes("/v1/feed"),
  "README must document the complete feed endpoint");
assert(debugConfig.includes("/v1/feed") && releaseConfig.includes("/v1/feed"),
  "default Xcode configurations must point to the Worker feed route");
assert(install.includes("GitHub") && install.includes("ZIP") && install.includes("TrollStore"),
  "install guide must explain artifact download, extraction, and TrollStore installation");

console.log("PASS: Task 14 CI, packaging, and beginner documentation contracts are present");
