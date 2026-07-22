# Task 6 TDD evidence

Task 6 was developed on Linux. Linux source contracts record the red/green
cycle, but they do not replace compilation or XCTest execution with Xcode.

## RED: `HomeViewModel` did not exist

After adding `GTA6CountdownTests/HomeViewModelTests.swift`, this command was
run before any Task 6 production implementation was added:

```sh
test -f GTA6CountdownTests/HomeViewModelTests.swift && echo 'XCTest created'; node - <<'NODE'
const fs=require('fs');
const vm='GTA6Countdown/Features/Home/HomeViewModel.swift';
if (!fs.existsSync(vm)) throw new Error('RED: HomeViewModel does not exist');
NODE
```

Observed output:

```text
XCTest created
[stdin]:3
if (!fs.existsSync(vm)) throw new Error('RED: HomeViewModel does not exist');
                        ^

Error: RED: HomeViewModel does not exist
    at [stdin]:3:31
    at runScriptInThisContext (node:internal/vm:219:10)
    at node:internal/process/execution:451:12
    at [stdin]-wrapper:6:24
    at runScriptInContext (node:internal/process/execution:449:60)
    at evalFunction (node:internal/process/execution:283:30)
    at evalTypeScript (node:internal/process/execution:295:3)
    at node:internal/main/eval_stdin:51:5
    at Socket.<anonymous> (node:internal/process/execution:205:5)
    at Socket.emit (node:events:520:35)

Node.js v24.14.0
```

## GREEN: Task 6 source contract and regressions

After implementing the homepage, this Task 6 source contract was run:

```sh
node - <<'NODE'
const fs=require('fs');
const files={
 vm:fs.readFileSync('GTA6Countdown/Features/Home/HomeViewModel.swift','utf8'),
 home:fs.readFileSync('GTA6Countdown/Features/Home/HomeView.swift','utf8'),
 hero:fs.readFileSync('GTA6Countdown/Features/Home/CountdownHeroView.swift','utf8'),
 progress:fs.readFileSync('GTA6Countdown/Features/Home/ReleaseProgressView.swift','utf8'),
 root:fs.readFileSync('GTA6Countdown/App/RootTabView.swift','utf8'),
 tests:fs.readFileSync('GTA6CountdownTests/HomeViewModelTests.swift','utf8'),
};
for (const token of ['CountdownTicking','HomeLifecycleObserving','recalibrate()','updateReleaseDate','MilestoneMessage.text']) if (!files.vm.includes(token)) throw new Error(`missing VM contract ${token}`);
for (const token of ['calendarDaysRemaining','preciseDays','hours','minutes','seconds']) if (!files.hero.includes(token)) throw new Error(`missing hero contract ${token}`);
for (const token of ['等待历程','不代表游戏开发进度','accessibilityValue']) if (!files.progress.includes(token)) throw new Error(`missing progress contract ${token}`);
if (!files.home.includes('Image("GTA6HomeArtwork")') || !files.home.includes('LinearGradient')) throw new Error('missing artwork hook or readability gradient');
if (!files.root.includes('HomeView()')) throw new Error('home is not wired');
for (const token of ['testStartCalibratesImmediatelyAndEveryTickUsesCurrentClock','testEnteringBackgroundStopsTickerAndDoesNotAdvanceFromTicks','testReturningToForegroundImmediatelyRebuildsGregorianCalculatorAndRestartsTicker','testRemoteReleaseDateUpdateRecalculatesWithoutWaitingForTick','testReleaseStateUsesApprovedCopyAndZeroValues']) if (!files.tests.includes(token)) throw new Error(`missing test ${token}`);
console.log('PASS: Task 6 home source contract is complete');
NODE
```

Observed output:

```text
PASS: Task 6 home source contract is complete
```

The existing Linux regression gates were then run:

```sh
bash tests/project_structure_test.sh
node tests/countdown_source_contract_test.js
node tests/news_cache_contract_test.js
node tests/task4_services_contract_test.js
git diff --check
```

Observed output (`git diff --check` produced no output):

```text
PASS: parsed iOS project structure is valid
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
```

The committed implementation was also checked with the same regression gates,
the Task 6 contract, `git diff HEAD^ HEAD --check`, and a clean-worktree check.
Observed final output:

```text
PASS: parsed iOS project structure is valid
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: committed Task 6 home contracts are complete
PASS: clean worktree at 7fda9842f7839536966d262dccb75f0d358b4001
```

## macOS verification pending

This environment does not provide Xcode or an iOS simulator. The new
`HomeViewModelTests` have not yet run under XCTest, and the SwiftUI views have
not yet been compiled or rendered here. Both remain pending in the macOS CI
workflow.

## Quality follow-up RED: waiting-progress boundary model was absent

Before addressing the Task 6 quality review, tests were added for lifecycle
stop/restart behavior, remote-config mutation, and waiting-progress boundary
behavior. This source check was then run before implementation:

```sh
node - <<'NODE'
const fs=require('fs');
const source=fs.readFileSync('GTA6Countdown/Features/Home/ReleaseProgressView.swift','utf8');
if (!source.includes('ReleaseWaitingProgress')) throw new Error('RED: ReleaseWaitingProgress does not exist');
NODE
```

Observed output:

```text
[stdin]:3
if (!source.includes('ReleaseWaitingProgress')) throw new Error('RED: ReleaseWaitingProgress does not exist');
                                                ^

Error: RED: ReleaseWaitingProgress does not exist
    at [stdin]:3:55
    at runScriptInThisContext (node:internal/vm:219:10)
    at node:internal/process/execution:451:12
    at [stdin]-wrapper:6:24
    at runScriptInContext (node:internal/process/execution:449:60)
    at evalFunction (node:internal/process/execution:283:30)
    at evalTypeScript (node:internal/process/execution:295:3)
    at node:internal/main/eval_stdin:51:5
    at Socket.<anonymous> (node:internal/process/execution:205:5)
    at Socket.emit (node:events:520:35)

Node.js v24.14.0
```

## Quality follow-up GREEN

After the narrow fixes, a source contract checked safe optional artwork
loading and its gradient fallback, precise confirmation copy, Gregorian/time
zone reconstruction, progress clamping, and all new test cases. It printed:

```text
PASS: Task 6 quality source contracts are complete
```

The regression gates were rerun:

```sh
bash tests/project_structure_test.sh
node tests/countdown_source_contract_test.js
node tests/news_cache_contract_test.js
node tests/task4_services_contract_test.js
git diff --check
```

Observed output (`git diff --check` produced no output):

```text
PASS: parsed iOS project structure is valid
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
```

XCTest and SwiftUI compilation remain pending in macOS CI.
