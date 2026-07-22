# Task 8 TDD evidence: MyGTA community prediction map

Recorded on 2026-07-20 in the repository root.

## RED: map implementation absent

The Task 8 XCTest specification and source-contract test were added before the
three production map files. The runnable contract was then executed with:

```sh
node tests/task8_map_contract_test.js; test $? -ne 0
```

Observed output:

```text
FAIL: missing GTA6Countdown/Features/Map/MapView.swift
```

This failure established that the attributed map feature did not yet exist.

## RED: navigation policy not injectable

After adding the policy-injection XCTest case and tightening the runnable
contract to inspect production sources only, the contract was executed with:

```sh
node tests/task8_map_contract_test.js; test $? -ne 0
```

Observed output:

```text
FAIL: navigation policy must be injectable
```

The production policy was then moved behind `MapNavigationDeciding` and injected
into `MapViewModel`.

## GREEN: Task 8 contract and regressions

The complete runnable gate was executed with:

```sh
node tests/task8_map_contract_test.js && \
node tests/validate_project_structure.js && \
node tests/task7_news_presentation_contract_test.js && \
node tests/countdown_source_contract_test.js && \
node tests/news_cache_contract_test.js && \
node tests/task4_services_contract_test.js && \
bash tests/project_structure_test.sh && \
git diff --check
```

Observed output:

```text
PASS: Task 8 attributed community map contracts are present
PASS: parsed iOS project structure is valid
PASS: Task 7 news presentation contracts are present
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: parsed iOS project structure is valid
```

`git diff --check` produced no output and exited successfully.

## macOS XCTest status

`GTA6CountdownTests/MapNavigationTests.swift` covers the exact initial HTTPS URL,
same-site and external navigation decisions, rejection of HTTP/custom schemes,
loading failure and retry, navigation controls, browser fallback, and injected
policy/opener behavior.

These XCTest cases were **not executed in this Linux workspace** because neither
Xcode nor `xcodebuild` is installed. Running the `GTA6Countdown` scheme's XCTest
suite remains explicitly pending on macOS CI.

## Quality follow-up RED

Focused XCTest cases were added for effective-port enforcement, live history
state publication, web-content process termination, and the current committed
internal URL used by the browser fallback. The runnable production-source
contract was extended for KVO lifecycle management, process recovery, error
overlay isolation, and current-URL tracking, then executed with:

```sh
node tests/task8_map_contract_test.js; test $? -ne 0
```

Observed output:

```text
FAIL: web history state must be observed with KVO
```

## Quality follow-up GREEN

After the narrow implementation changes, the complete gate was executed with:

```sh
node tests/task8_map_contract_test.js && \
node tests/validate_project_structure.js && \
node tests/task7_news_presentation_contract_test.js && \
node tests/countdown_source_contract_test.js && \
node tests/news_cache_contract_test.js && \
node tests/task4_services_contract_test.js && \
bash tests/project_structure_test.sh && \
git diff --check
```

Observed output:

```text
PASS: Task 8 attributed community map contracts are present
PASS: parsed iOS project structure is valid
PASS: Task 7 news presentation contracts are present
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: parsed iOS project structure is valid
```

`git diff --check` again produced no output and exited successfully. The new and
existing XCTest cases remain pending execution on macOS CI for the same tooling
reason stated above.
