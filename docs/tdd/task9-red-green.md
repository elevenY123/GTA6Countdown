# Task 9 TDD evidence

## Red

Command (Linux structural contract):

```sh
node tests/task9_widget_contract_test.js
```

Observed before implementation:

```text
FAIL: missing GTA6CountdownWidgets/GTA6CountdownWidgets.swift
```

`GTA6CountdownTests/WidgetTimelineTests.swift` was also added first and references the not-yet-created `WidgetTimelinePlanner`, `WidgetCountdownContent`, `WidgetNewsSelection`, and `WidgetNewsRoute` APIs. Its expected compile failure can only be executed on the macOS/Xcode CI runner.

## Green

Linux-verifiable contract and regression commands:

```sh
node tests/task9_widget_contract_test.js
node tests/validate_project_structure.js
bash tests/project_structure_test.sh
node tests/countdown_source_contract_test.js
node tests/news_cache_contract_test.js
node tests/task4_services_contract_test.js
node tests/task7_news_presentation_contract_test.js
node tests/task8_map_contract_test.js
git diff --check
```

Observed after implementation:

```text
PASS: Task 9 WidgetKit source contract is valid
PASS: parsed iOS project structure is valid
PASS: parsed iOS project structure is valid
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: Task 7 news presentation contracts are present
PASS: Task 8 attributed community map contracts are present
```

The Swift XCTest suite, WidgetKit build, widget previews, and visual clipping checks require the macOS/Xcode CI gate; Swift/Xcode are unavailable in this Linux workspace.

## Review fixes — Red

After adding tests for daily/DST refresh planning, future cache timestamps,
bounded cover loading, response validation, and accessibility-size layout, the
updated Linux contract failed before the review fixes:

```text
FAIL: widgets must receive provider-loaded cover data instead of AsyncImage
```

The new XCTest cases also referenced not-yet-created timeline, image pipeline,
and layout-policy APIs.

## Review fixes — Green

The Linux source contracts and all earlier regressions pass after the fixes:

```text
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: Task 7 news presentation contracts are present
PASS: Task 8 attributed community map contracts are present
PASS: Task 9 WidgetKit source contract is valid
PASS: parsed iOS project structure is valid
```

The app scheme already builds the embedded widget target and runs
`GTA6CountdownTests`, including the new timeline/DST, cache-age, bounded-image,
response-validation, and layout-policy tests, in macOS GitHub Actions. Widget
Gallery previews and screenshot clipping inspection cannot run in this Linux
workspace and remain an explicit external visual gate.

## Streaming/deadline review — Red

Tests were added first for a chunked `URLProtocol` response that exceeds its
limit mid-transfer, a partial-result overall cover deadline, cancellation of
slow loads, and cover-cache expiry/corruption. Before implementation:

```text
FAIL: cover transport must enforce its limit while streaming
```

## Streaming/deadline review — Green

The implementation now uses a per-request `URLSessionDataDelegate` transport.
It rejects oversized `Content-Length` before allowing the body, cancels as soon
as accumulated chunks cross 4 MB, and resolves its checked continuation through
one lock-guarded terminal path. The cover pipeline has one four-second overall
deadline, production concurrency remains two to cap compressed in-flight data
near 8 MB, and canceled URL session tasks return partial covers without blocking
the text timeline. Disk covers expire after 24 hours; corrupt ImageIO data is
deleted and fetched again.

All Linux contracts, earlier regressions, structure validation, and
`git diff --check` pass. The new streaming `URLProtocol`, deadline/cancellation,
and TTL XCTest cases still require the macOS/Xcode CI gate.
