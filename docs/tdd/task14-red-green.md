# Task 14 TDD evidence

## RED

`bash tests/task14_ipa_contract_test.sh` was run before the validator existed.
It failed at the first malformed fixture because `scripts/validate-ipa.sh` could
not be executed. This proves the package contract was not already implemented.

## GREEN

After implementing `scripts/validate-ipa.sh`, the same command passed. The
contract suite created five packages in a temporary directory and verified:

- an empty ZIP is rejected;
- a ZIP without a Payload app is rejected;
- an app without the embedded Widget is rejected;
- an app declaring iOS 17.0 instead of iOS 16.0 is rejected; and
- a structurally valid fixture is accepted.

## Review regression RED/GREEN

The CI contract was extended after review to require the supported `macos-15`
runner, explicit Xcode 16.4 selection/version output, and `push` builds limited
to `main`. It failed against the initial workflow (`macos-14` and unrestricted
push), then passed after those workflow fixes.

The first real GitHub Actions run then failed before creating any jobs because
job-level `env` cannot use the `runner` context. `actionlint` reproduced the
failure at `DERIVED_DATA`; the contract now rejects that expression and the
workflow uses an absolute runner-local temporary path instead.
