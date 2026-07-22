# Task 4 TDD Evidence: News Repository and Image Cache

Date: 2026-07-20

## RED

Tests were added before production implementation for:

- successful network refresh, persistence, and injected widget reload;
- HTTP, timeout, malformed payload, and unsupported-schema cache fallback;
- a distinct no-cache unavailable state;
- coalescing concurrent repository refreshes;
- rejecting HTTP errors and HTML masquerading as an image;
- coalescing concurrent image downloads, disk reuse, safe hashed filenames, and bounded eviction.

The Linux wiring gate was then run:

```text
$ node tests/task4_services_contract_test.js
Error: missing GTA6Countdown/Services/NewsAPIClient.swift
exit code 1
```

This is the expected RED failure because the Task 4 service layer did not exist.

## GREEN

After implementing the minimum service layer, all executable Linux gates passed:

```text
$ node tests/task4_services_contract_test.js
Task 4 service contract validated.

$ bash tests/project_structure_test.sh
PASS: parsed iOS project structure is valid

$ node tests/news_cache_contract_test.js
PASS: news decoding and shared cache source contracts are complete

$ node tests/countdown_source_contract_test.js
PASS: countdown source wiring is complete

$ git diff --check
(no output; exit code 0)
```

The host has no Swift, Xcode, `xcodebuild`, or XcodeGen installation. The authoritative XCTest compile and run therefore remains pending the macOS GitHub Actions build.

## Implementation Notes

- `NewsAPIClient` accepts injected session and endpoint values and rejects non-2xx responses, malformed payloads, unsupported schemas, duplicate IDs, and invalid required article values.
- `NewsRepository` exposes network/cache/unavailable states, preserves the payload timestamp during fallback, reports a nonblocking issue, coalesces refreshes, persists successful payloads, and invokes only an injected widget reload abstraction.
- `ImageCache` is actor-isolated, coalesces downloads, requires both an image MIME type and recognized byte signature, hashes the full URL with SHA-256, and evicts least-recently-used disk entries to remain under its configured limit.

## Review Fix: Production Widget Reloading

A spec review found that the original production default was a no-op reloader. A regression test and source-contract gate were added first. The gate produced the expected RED result:

```text
$ node tests/task4_services_contract_test.js
Error: production widget integration missing
exit code 1
```

`SystemWidgetReloader` was then added with a production action backed by `WidgetCenter.shared.reloadAllTimelines()`, and it became the repository default. Its action remains injectable so XCTest can prove delegation without invoking the WidgetKit runtime; `NoopWidgetReloader` remains available only when explicitly requested by a test or preview.

## Quality Review Fixes

Important quality findings were converted into regression tests before implementation. The expanded contract produced the expected RED result:

```text
$ node tests/task4_services_contract_test.js
Error: in-memory last-good fallback missing
exit code 1
```

The GREEN implementation adds:

- an in-memory last-good payload that survives cache-write failure and is returned after a later network and disk-cache failure;
- top-level and remote-config schema compatibility checks, nonblank presentation fields, official credibility consistency, and pinned-official integrity checks;
- an image response-size limit independent from the total disk budget;
- `URLSession.download(from:)` temporary-file downloads with file-size inspection before `Data` allocation;
- a dedicated owned image-cache directory that ignores unrelated sentinel files and evicts only SHA-256 `.image` entries;
- startup, first-access, and cache-hit maintenance, including oversized-entry and owned stale-temp cleanup;
- coalesced same-URL downloads with individually cancellable waiters, cancellation of shared work after its last waiter leaves, and a bounded distinct-URL download limiter.

The executable Linux contracts and structural regressions returned GREEN after these changes. Authoritative XCTest compilation and runtime verification remain assigned to macOS CI because this host has no Swift/Xcode toolchain.

## Follow-up: Freshness and Maintenance Latency

Two additional regression tests were written before the follow-up implementation:

- disk payload A → newer network payload B with failed save → failed network refresh with disk A must preserve B;
- startup maintenance must run once, while repeated image-cache hits must not repeat a directory scan.

The expanded contract produced the expected RED result:

```text
$ node tests/task4_services_contract_test.js
Error: stale disk precedence missing
exit code 1
```

The repository now compares `updatedAt` and retains the freshest payload. Image-cache initialization now only creates its owned directory and schedules one detached startup maintenance task. A deterministic `waitForMaintenance()` test hook observes completion. Request and hit paths perform only URL hashing, single-file metadata/signature validation, and access-date updates. Successful writes wait for the one startup inventory and then maintain the disk bound through the in-memory `diskEntries` index and `trackedDiskSize`, without rescanning the directory.

## Final Accounting Hardening

Focused tests then injected maintenance metadata and deletion failures. Before implementation, the contract produced the expected RED result:

```text
$ node tests/task4_services_contract_test.js
Error: maintenance failure is collapsed
exit code 1
```

Startup maintenance now returns an explicit success inventory or failure. Per-file metadata errors and unconfirmed deletions fail maintenance rather than silently excluding surviving bytes. Persistent image writes require an established accurate inventory; after failure, downloads still return valid uncached data and each later write attempt first retries maintenance. Incremental eviction removes bytes from accounting only after the file operation succeeds and absence is confirmed. The injected failure tests verify that old files survive, no new cache file is written, and maintenance is retried.

## Transactional Persistence

The final focused tests cover a response that fits the memory limit but exceeds the disk-item limit, and a post-startup incremental eviction whose deletion fails. The contract first produced the expected RED result:

```text
$ node tests/task4_services_contract_test.js
Error: persist result is ambiguous
exit code 1
```

Persistence now returns an explicit `committed`, `notCacheable`, or `failure` result. Oversized disk items return uncached without invoking accounting. For cacheable data, required LRU capacity is reserved through confirmed evictions before the destination is committed. A failed eviction therefore leaves the new destination absent, surviving old bytes tracked, and actual disk use within the configured bound.
