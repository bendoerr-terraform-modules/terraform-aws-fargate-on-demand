# Tripwire forced-red receipts — 2026-08-20

> *"Forced red beats witnessed green."* — code-kitten
> *"A branch that works and a branch that has never once been run look identical from the
> outside, and only one of them is knowledge."* — Lilith (what these receipts buy is not
> correctness — the branches were right before any of this ran — it is falsifiability)

The five arms implement **11 sub-directions**. The natural pre-fix tree fires 4; the seven
plants below fire the other 7, one at a time, each reverted with the tracked tree verified
clean before the next. Receipt 9 proves the refusal contract (rc=2, never a silent pass).
Every rc line is measured without a pipe (`cmd > f 2>&1; echo rc=$? >> f`).

## 1. Natural red — pre-fix tree at `3b52aa8` (fires test-dir ×1, matrix-missing, dependabot tf-missing + gomod-missing)

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: OK
ARM exemptions: OK
population: 8 modules, 6 test dirs, 0 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 2. Plant: golangci entry removed (`"modules/persistence/test"` deleted from workdirs) — golangci missing-direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: RED
  - modules/persistence/test has a test dir but is missing from golangci_workdirs
ARM exemptions: OK
population: 8 modules, 6 test dirs, 0 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 3. Plant: exemption `ghost-module` — exemptions nonexistent-module direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: OK
ARM exemptions: RED
  - exemption 'ghost-module' names a module that does not exist
population: 8 modules, 6 test dirs, 1 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 4. Plant: exemption `persistence` — exemptions stale (grew-a-test) direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: OK
ARM exemptions: RED
  - exemption 'persistence' is stale: the module has since grown a test dir
population: 8 modules, 6 test dirs, 1 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 5. Plant: matrix entry `modules/ghost/test` — matrix ghost (configured-but-not-on-disk) direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
  - modules/ghost/test is in the matrix but has no test dir on disk
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: OK
ARM exemptions: OK
population: 8 modules, 6 test dirs, 0 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 6. Plant: dependabot terraform dir `/modules/ghost` — dependabot terraform-ghost direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/ghost is in dependabot(terraform) but not on disk
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: OK
ARM exemptions: OK
population: 8 modules, 6 test dirs, 0 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 7. Plant: dependabot gomod dir `/modules/ghost/test` — dependabot gomod-ghost direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
  - /modules/ghost/test is in dependabot(gomod) but not on disk
ARM golangci: OK
ARM exemptions: OK
population: 8 modules, 6 test dirs, 0 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 8. Plant: golangci workdir `modules/ghost/test` — golangci ghost direction

```text
ARM test-dir: RED
  - modules/efs-access has no test/ dir and no exemption
  - modules/service has no test/ dir and no exemption
ARM matrix: RED
  - modules/notice-parameter-store/test has a test dir but is missing from the test.yml matrix
ARM dependabot: RED
  - /modules/efs-access has no terraform dependabot entry
  - /modules/notice-github has no terraform dependabot entry
  - /modules/notice-parameter-store has no terraform dependabot entry
  - /modules/service has no terraform dependabot entry
  - /modules/notice-github/test has no gomod dependabot entry
  - /modules/notice-parameter-store/test has no gomod dependabot entry
ARM golangci: RED
  - modules/ghost/test is in golangci_workdirs but has no test dir on disk
ARM exemptions: OK
population: 8 modules, 6 test dirs, 0 exemptions
COVERAGE TRUTH: RED
rc=1
```

## 9. Refusal control: exemptions file absent — NOT MEASURED, never a pass

```text
NOT MEASURED - .github/coverage-exemptions.txt missing - deleting the allowlist is not a way to pass
rc=2
```

## 10. PR A end-state green — all five arms OK with exactly one dated exemption

```text
ARM test-dir: OK
ARM matrix: OK
ARM dependabot: OK
ARM golangci: OK
ARM exemptions: OK
population: 8 modules, 7 test dirs, 1 exemptions
COVERAGE TRUTH: PASS
rc=0
```
