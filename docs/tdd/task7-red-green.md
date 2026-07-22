# Task 7 TDD evidence — news experience

## RED

Presentation, route, and UI-flow tests were added before the feature files:

- `GTA6CountdownTests/NewsPresentationTests.swift`
- `GTA6CountdownUITests/NewsFlowTests.swift`
- `tests/task7_news_presentation_contract_test.js`

The locally executable contract failed against base `4b3f472`:

```text
$ node tests/task7_news_presentation_contract_test.js
FAIL: missing GTA6Countdown/Features/News/NewsListView.swift
```

The XCTest suite additionally named the expected official-pin validation,
newest-first ordering, credibility copy, Unicode-safe stable route, cached
nonblocking failure, and no-cache unavailable behavior before implementation.

## GREEN

After implementing the news presentation layer and views:

```text
$ for test in tests/*.js; do node "$test"; done
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: Task 7 news presentation contracts are present
PASS: parsed iOS project structure is valid

$ for test in tests/*.sh; do bash "$test"; done
PASS: parsed iOS project structure is valid

$ git diff --check
# no output
```

`xcodebuild` is unavailable in the Linux implementation environment. The new
XCTest and XCUITest files are included in the XcodeGen targets and remain to be
executed by the existing macOS GitHub Actions workflow.

## Covered behavior

- Only the configured, internally consistent Rockstar official article is pinned.
- The pinned article is excluded from newest-first ordinary rows.
- Cached content remains visible when refresh fails; no-cache failure is recoverable.
- Every card has an asynchronous cached cover with a unified fallback.
- Details contain a short summary and source metadata, never copied full text.
- HTTP(S) source URLs open in `SFSafariViewController`.
- Stable article-ID URLs use `gta6countdown://news/article?id=...` and the scheme is registered.
- iOS 16-compatible loading, empty, unavailable, refresh, light/dark, Dynamic Type,
  and accessibility affordances are present.

## Follow-up RED — canonical topics and news-specific covers

Review exposed that IDs alone were insufficient to prevent two outlets from
showing the same story, and that the shared generic placeholder did not carry
the approved GTA VI visual language. Tests were expanded first for the full
selection order, pinned-topic suppression, retained service metadata, source
and time copy, empty/refresh lifecycle, summary-only detail, injected original
URL handoff, and the pinned-card UI flow.

```text
$ node tests/task7_news_presentation_contract_test.js
FAIL: news rows must deduplicate canonical topics
```

## Follow-up GREEN

`NewsPresentation` now chooses one unchanged service article per
`canonicalTopicKey` using the deterministic order: internally consistent
official, stronger meaningful credibility, newest timestamp, then ascending
stable ID. The entire pinned topic is omitted from rows. News cards and details
share a Vice-palette `VI`/newspaper placeholder with explicit accessibility
copy. A bundled fixture drives the XCUITest without network or Safari handoff.

```text
$ for test in tests/*.js; do node "$test"; done
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: Task 7 news presentation contracts are present
PASS: parsed iOS project structure is valid

$ for test in tests/*.sh; do bash "$test"; done
PASS: parsed iOS project structure is valid

$ git diff --check
# no output
```

The expanded XCTest/XCUITest suite remains gated on the existing macOS CI,
because this implementation environment does not include `xcodebuild`.

## Quality follow-up RED — validated async cache boundary

The next review found that network validation was private to the HTTP client,
while synchronous repository initialization decoded disk data on `MainActor`.
It also found that canonical topic grouping did not normalize key casing and
row construction allocated Foundation formatters repeatedly. Tests and source
contracts were added first for all ingress points, invalid old/contradictory
cache payloads, coalesced hydration, injected invalid network and bundle data,
normalized topic keys, and a single coherent accessibility representation.

```text
$ node tests/task7_news_presentation_contract_test.js
FAIL: missing reusable NewsPayloadValidator
```

## Quality follow-up GREEN

- `NewsPayloadValidator` is shared by HTTP, repository, actor cache, and bundled
  fixture paths.
- `NewsPayloadCacheActor` owns all synchronous SharedCache data and Codable IO;
  `NewsRepository` awaits it and publishes state only from `MainActor`.
- Repository initialization performs no disk read. Explicit hydration is
  coalesced and `NewsViewModel.load()` performs hydrate then refresh once.
- Invalid cached payloads become cache-read failures and can never enter
  presentation or network-failure fallback.
- Date copy uses iOS FormatStyle values instead of per-row formatter objects.
- Canonical topic keys trim whitespace and use POSIX locale case folding.
- Card cover internals are decorative; VoiceOver receives one source/time-rich
  row or official-card label.

```text
$ for test in tests/*.js; do node "$test"; done
PASS: countdown source wiring is complete
PASS: news decoding and shared cache source contracts are complete
Task 4 service contract validated.
PASS: Task 7 news presentation contracts are present
PASS: parsed iOS project structure is valid

$ for test in tests/*.sh; do bash "$test"; done
PASS: parsed iOS project structure is valid

$ git diff --check
# no output
```

The actor, validator, XCTest, and XCUITest compile/run gate remains the existing
macOS GitHub Actions workflow because local `xcodebuild` is unavailable.

## Final concurrency RED — refresh authority

Focused race tests suspend the first hydration cache read, allow a transport
failure plus valid fallback cache refresh to finish, and then resume hydration
with both a stale hit and a failure. A second test has two callers await one
suspended refresh and captures `currentState` immediately after each returns.

```text
$ node tests/task7_news_presentation_contract_test.js
FAIL: late hydration needs a refresh-authority generation guard
```

## Final concurrency GREEN

Repository state now has a monotonic generation. Hydration captures its initial
generation and may publish only when that generation is still current, so no
late hit or failure can replace any completed refresh result. The shared refresh
task applies state and advances the generation on `MainActor` before completing;
all coalesced waiters therefore return with synchronized `currentState`.

```text
$ node tests/task7_news_presentation_contract_test.js
PASS: Task 7 news presentation contracts are present

$ git diff --check
# no output
```

The deterministic suspended-cache and two-caller XCTest cases remain part of
the macOS CI compile/run gate.
