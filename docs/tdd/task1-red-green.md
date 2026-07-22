# Task 1 TDD evidence

## RED — before project implementation

Command:

```sh
bash tests/project_structure_test.sh
```

Output and exit status:

```text
FAIL: missing project.yml
exit=1
```

## GREEN — after minimal implementation

Command:

```sh
bash tests/project_structure_test.sh
```

Output and exit status:

```text
PASS: iOS project structure is valid
exit=0
```

The Linux development host did not have `xcodegen`, `xcodebuild`, or Swift installed. Xcode project generation and simulator compilation remain pending verification in macOS CI.

## Structural validator upgrade

The original substring checks were replaced with a zero-dependency YAML subset parser. Before renaming the Widget source directory, the upgraded validator observed the expected failure:

```sh
bash tests/project_structure_test.sh
```

```text
FAIL: GTA6CountdownWidget must source GTA6CountdownWidgets
exit=1
```

After aligning the source directory and project configuration with `GTA6CountdownWidgets/`, the same command passed:

```text
PASS: parsed iOS project structure is valid
exit=0
```

GitHub Actions now gates XcodeGen generation, simulator build, and unit tests on macOS. Those steps remain locally unverified because this Linux host has no Xcode toolchain.
