# Task 10 TDD evidence — Worker news domain pipeline

Date: 2026-07-20

## RED 1 — missing domain implementation

After writing `backend/test/pipeline.test.ts` first:

```text
$ cd backend && npm test
FAIL test/pipeline.test.ts
Error: Cannot find module '../src/domain/credibility'
Test Files  1 failed (1)
```

This proved the tests were exercising modules that had not been implemented.

## GREEN 1 — base normalization pipeline

The minimum article model, credibility classifier, OpenCC wrapper, relevance
filter, normalizer, and exact-key deduplicator were then implemented.

```text
$ npm test
Test Files  1 passed (1)
Tests       25 passed (25)

$ npm run typecheck
tsc --noEmit
```

## RED 2 — two uncovered design rules

Two tests were added before their implementation: an untraceable leak must be
dropped, and similar trailer-event titles must merge even without an upstream
topic key.

```text
$ npm test
Test Files  1 failed (1)
Tests       2 failed | 25 passed (27)

FAIL ... drops untraceable leaks but retains a leak with valid original provenance
expected ... to be null

FAIL ... conservatively groups similar trailer-event titles without an upstream topic key
expected ... to have a length of 2 but got 3
```

## GREEN 2 — provenance gate and conservative similarity

The normalizer now rejects untraceable leaks. The deduplicator uses exact
non-empty keys first, then conservative event-family signatures: matching
trailer numbers, matching release dates, or a guarded title-token similarity.

```text
$ npm test
Test Files  1 passed (1)
Tests       27 passed (27)

$ npm run typecheck
tsc --noEmit

$ npm audit --audit-level=high
found 0 vulnerabilities
```

A final RED check also proved that two URLs from one outlet were being counted
as two related media sources (`expected 0, received 1`). Source counting was
changed to use the normalized attributed outlet identity. The final suite is
29/29, including a guard that trailer 1 and trailer 2 never merge.

## Review RED — trust boundaries and total ordering

Specification review added tests for three Important boundaries before their
fixes: repost provenance must not grant official authority, Chinese content is
required in the title itself, and equally ranked duplicate candidates must not
depend on input order.

```text
$ npm test
Test Files  1 failed (1)
Tests       4 failed | 30 passed (34)

FAIL ... requires substantive Chinese in the title independently ...
expected true to be false

FAIL ... never grants official status through repost provenance
expected 'official' to be 'media'

FAIL ... keeps a traceable leak unverified even when its original URL is Rockstar
expected 'official' to be 'unverified'

FAIL ... uses stable fields when credibility, time, and id are all tied
expected forward output to deeply equal reversed output
```

## Review GREEN — authority isolation and deterministic ties

Credibility now uses only the article's own adapter identity and own trusted
Chinese Newswire URL; `isLeak` takes precedence. Original-source metadata is
used only for display attribution and source counting. Title and summary each
have their own Chinese-content threshold after excluding allowed GTA/Rockstar
proper names. Both dedupe comparators finish with a stable key covering every
output field.

```text
$ npm test
Test Files  1 passed (1)
Tests       35 passed (35)

$ npm run typecheck
tsc --noEmit
```

## Re-review RED/GREEN — raw-value tie collisions

Re-review identified that NFKC/lowercasing in the final stable key could make
two different output titles compare equal. A case-only title variant reproduced
the input-order dependency:

```text
$ npm test
Test Files  1 failed (1)
Tests       1 failed | 35 passed (36)
FAIL ... keeps deterministic raw output when normalized tie-break fields collide
```

The final key now serializes a fixed array containing every raw output field.
JSON array encoding preserves case and Unicode representation and avoids the
delimiter ambiguity of string concatenation. Completely identical outputs may
still compare equal safely.

```text
$ npm test
Test Files  1 passed (1)
Tests       36 passed (36)
```

The audit originally identified a development-only Vitest advisory in 3.2.4;
updating to 3.2.7 removed it. `opencc-js` is MIT-licensed, has no production
dependencies, and the Worker code imports its browser-compatible `t2cn` entry.

## Quality-review RED — bounded and transport-safe records

Quality review added the following tests before implementation: finite bounded
related-source counts, globally namespaced IDs, strict zoned ISO timestamps,
credential and image-host URL safety, pinned-official selection, explicit topic
isolation, and adapter-identity source counting.

```text
$ npm test
Test Files  1 failed (1)
Tests       7 failed | 36 passed (43)
```

Each failure mapped to one requested boundary. The implementation introduced a
`PipelineArticle` carrying attributed adapter identity and explicit-topic state,
plus `toNewsArticle` as the only public Swift-contract projection. Stable IDs use
a collision-free length-delimited tuple of adapter ID, bounded upstream ID, and
the article's own canonical source URL; no short hash is used.

URL tests were then extended for trailing-dot localhost/local-domain spellings,
and stable-ID conflict tests verified that repeated identities always collapse:

```text
$ npm test
Test Files  1 failed (1)
Tests       2 failed | 44 passed (46)
```

The final implementation also uses deterministic complete-link fuzzy groups,
keeps records with different explicit upstream topics separate, and precomputes
title signatures once per record. Public serialization is tested against the
exact twelve Swift `NewsArticle` fields and contains no internal keys.

```text
$ npm test
Test Files  1 passed (1)
Tests       46 passed (46)

$ npm run typecheck
tsc --noEmit
```

Task 13 must include the full `opencc-js` MIT license in release acknowledgements;
`backend/THIRD_PARTY_NOTICES.md` tracks that packaging obligation.
