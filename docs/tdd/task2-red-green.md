# Task 2 TDD evidence

## RED — before countdown implementation

The XCTest specification was written first. Because this Linux host has neither Swift nor Xcode, a zero-dependency source-contract test provides a local executable gate while macOS CI remains authoritative for runtime behavior.

Command:

```sh
node tests/countdown_source_contract_test.js
```

Output and exit status:

```text
FAIL: missing CountdownState.swift
exit=1
```

## GREEN — after minimal implementation

Commands:

```sh
node tests/countdown_source_contract_test.js
bash tests/project_structure_test.sh
git diff --check
```

Output:

```text
PASS: countdown source contract is complete
PASS: parsed iOS project structure is valid
```

`git diff --check` also exited successfully without output. `CountdownCalculatorTests` covers local-midnight release resolution in two time zones, injected time, component decomposition, release clamping, a daylight-saving boundary, all approved milestone messages, and the default message. Running that XCTest suite is pending macOS CI because `xcodebuild` is unavailable on this host.

## Review fix cycle

Tests were extended before production code to cover a Buddhist device calendar, natural-day milestone behavior at midday and 23:59:59 for 100, 7, and 1 days, and the one-second release boundary. The Linux wiring gate then produced the expected RED result:

```text
FAIL: production calendar must derive device settings explicitly
exit=1
```

The implementation now creates a Gregorian production calendar while carrying over the device locale and time zone. `CountdownState` separates precise countdown components (`preciseDays`, hours, minutes, seconds) from the local-date headline value (`calendarDaysRemaining`), and milestone copy uses only the latter. After implementation, the wiring test, project structure test, and `git diff --check` all pass. Runtime XCTest remains pending macOS CI.
