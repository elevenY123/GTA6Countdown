# Task 3 RED/GREEN record

## RED

Command:

```sh
node tests/news_cache_contract_test.js .
```

Observed failure before implementation:

```text
FAIL: missing GTA6Countdown/Shared/News/NewsArticle.swift
```

The XCTest cases were authored first as the authoritative macOS/iOS checks. They cannot run in this Linux workspace because Swift/Xcode is unavailable.

## GREEN

Commands:

```sh
node tests/news_cache_contract_test.js .
node tests/countdown_source_contract_test.js .
bash tests/project_structure_test.sh
git diff --check
```

Observed results:

```text
PASS: news decoding and shared cache source contracts are complete
PASS: countdown source wiring is complete
PASS: parsed iOS project structure is valid
```

The authoritative `NewsDecodingTests` and `SharedCacheTests` remain pending the macOS GitHub Actions build.

## Quality follow-up RED/GREEN

Tests were added first for unsafe filenames, partial-write cleanup, and preservation of a valid non-default remote release date.

RED:

```text
FAIL: unsafe cache filenames must be rejected
```

GREEN uses the same command set above. The injected writer test now creates a partial temporary file and throws; `SharedCache` reports `writeFailed` and leaves the cache directory empty.
