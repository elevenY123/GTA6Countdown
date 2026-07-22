# Task 5 TDD evidence

Task 5 was developed on Linux. Linux source contracts are evidence for the red/green cycle; they are not a substitute for an Xcode UI-test run.

## Initial RED: stable root-tab identifiers did not exist

Command (as run):

```sh
test -f GTA6CountdownUITests/RootNavigationTests.swift && echo 'UI test created'; node - <<'NODE'
const fs=require('fs');
const root=fs.readFileSync('GTA6Countdown/App/RootTabView.swift','utf8');
for (const id of ['root-tab-home','root-tab-news','root-tab-map']) {
  if (!root.includes(id)) throw new Error(`RED: missing ${id}`);
}
NODE
```

Observed output:

```text
UI test created
[stdin]:4
  if (!root.includes(id)) throw new Error(`RED: missing ${id}`);
                          ^

Error: RED: missing root-tab-home
    at [stdin]:4:33
    at runScriptInThisContext (node:internal/vm:219:10)
    at node:internal/process/execution:451:12
    at [stdin]-wrapper:6:24
    at runScriptInContext (node:internal/process/execution:449:60)
    at evalFunction (node:internal/process/execution:283:30)
    at evalTypeScript (node:internal/process/execution:295:3)
    at node:internal/main/eval_stdin:51:5
    at Socket.<anonymous> (node:internal/process/execution:201:5)
    at Socket.emit (node:events:520:35)

Node.js v24.14.0
```

## Initial GREEN: Linux contracts and regressions

Observed output after implementation:

```text
Task 5 source contracts green.
project.yml parsed and UI test target is wired
PASS: parsed iOS project structure is valid
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
```

`git diff --check` also completed with no output.

## QA contract append: themes, frames, screenshots, and CI

Before the QA additions, this source contract was run:

```sh
node - <<'NODE'
const fs=require('fs');
const ui=fs.readFileSync('GTA6CountdownUITests/RootNavigationTests.swift','utf8');
const workflow=fs.readFileSync('.github/workflows/ios-smoke.yml','utf8');
for (const token of ['UIUserInterfaceStyle','XCTAttachment','frame.intersects','window.frame.contains']) {
  if (!ui.includes(token)) throw new Error(`RED: UI test missing ${token}`);
}
if (!workflow.includes('only-testing:GTA6CountdownUITests')) throw new Error('RED: workflow does not run UI tests explicitly');
console.log('Task 5 QA source contract green.');
NODE
```

Observed RED output:

```text
[stdin]:5
  if (!ui.includes(token)) throw new Error(`RED: UI test missing ${token}`);
                           ^

Error: RED: UI test missing UIUserInterfaceStyle
    at [stdin]:5:34
    at runScriptInThisContext (node:internal/vm:219:10)
    at node:internal/process/execution:451:12
    at [stdin]-wrapper:6:24
    at runScriptInContext (node:internal/process/execution:449:60)
    at evalFunction (node:internal/process/execution:283:30)
    at evalTypeScript (node:internal/process/execution:295:3)
    at node:internal/main/eval_stdin:51:5
    at Socket.<anonymous> (node:internal/process/execution:201:5)
    at Socket.emit (node:events:520:35)

Node.js v24.14.0
```

After adding light/dark launches, maximum Dynamic Type frame assertions, retained screenshots, explicit UI-test execution, and result-bundle upload, the updated Linux source contract printed:

```text
Task 5 QA source contract green.
```

## macOS QA still required

No simulator or Xcode UI tests were run on Linux. The macOS CI job must run `GTA6CountdownUITests`, retain its `.xcresult`, and a person must visually inspect the attached light/dark and default/Accessibility XXXL screenshots for clipping or visual truncation. Accessibility labels and frames cannot deterministically prove glyph-level visual truncation.
