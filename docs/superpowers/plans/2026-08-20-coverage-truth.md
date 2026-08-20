# Coverage Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the module population, CI test matrix, dependabot config, and golangci workdirs
provably agree in `terraform-aws-fargate-on-demand` — and add the missing tests so agreement
means coverage, not exemption.

**Architecture:** Two PRs. **PR A** (branch `patrol/coverage-truth`): a five-arm coverage
tripwire (proven red per-arm before any fix), matrix + dependabot + golangci roster fixes, an
`efs-access` terratest, modernization of the never-run `notice-parameter-store` test, and a
one-entry dated exemption for `service`. **PR B** (branch `patrol/service-coverage`, after A
merges): a `service` example + terratest parked at desired-count-0, retiring the exemption so
the allowlist ends empty. The hole is **structural, not an oversight** — this repo has no root
module; its entire public surface is the eight submodules, so only a per-submodule invariant
can ever cover it (Lilith's premise verification: 0 of 64 `.tf` files wire `service`, positive
control passed).

**Tech Stack:** Terraform (module floor `>= 1.9.0` for `service`, `>= 1.3.0` elsewhere),
Go 1.26.0 + terratest v1.0.1, aws-sdk-go-v2, Python 3 + PyYAML (tripwire), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-20-coverage-truth.md` (same branch).

## Global Constraints

- Repo: `bendoerr-terraform-modules/terraform-aws-fargate-on-demand`. Working clone:
  `/tmp/claude-1001/-home-ombb-omyac/e9a3f00b-f8c0-490b-bb28-3cab5a5845aa/scratchpad/fod`.
- Commits: signed (email `oldmanbendobot@gmail.com` already set in clone), gitmoji prefix,
  unicode emoji only (never shortcodes).
- YAML edits must pass `npx prettier@3.3.3 --check` (org reviewdog-prettier lints workflow
  YAML; never column-align).
- Test runs against the sandbox account use `AWS_PROFILE=brd-sndbx-ue1-core-bendoerr`
  (account 234656776442) — same account CI assumes. Always `terraform destroy` via the
  test's own defer; never leave resources (nightly nuke is backstop, not plan).
- CI truth: `.github/workflows/test.yml` job `terratest`, matrix key
  `jobs.terratest.strategy.matrix.project`, serialized (`max-parallel: 1`, concurrency
  group `sandbox-test`, `cancel-in-progress: false`).
- New Go test dirs: `go 1.26.0`, `terratest v1.0.1`, `.golangci.yml` copied from
  `modules/persistence/test/.golangci.yml` (lint.yml lists workdirs explicitly).
- The `lint` job is a reusable-workflow call — steps CANNOT be added to it. The tripwire
  step goes in the `paperwork` job (egress-blocked to `api.github.com:443`,`github.com:443`;
  the tripwire must therefore be purely local — no installs, no network).
- Wall-clock honesty: matrix grows 5 → 8 serialized projects (~12 min each observed);
  PR A takes it to 7 (~84 min), PR B to 8 (~96 min). That crosses the spec's "~60 min →
  discuss splitting" line — both PR bodies MUST state the measured total so the discussion
  is triggered, not discovered.
- Local module fetch: the examples' `git@github.com:` sources work locally via go-getter's
  ssh:// normalization + this box's global `insteadOf` rewrite (measured with
  `terraform get`). Do NOT probe with raw scp-form `git ls-remote` — port 22 is blocked
  and it hangs; that is not a defect.

______________________________________________________________________

## PR A — branch `patrol/coverage-truth`

### Task 1: Coverage-truth tripwire + per-arm forced-red receipts

**Files:**

- Create: `.github/scripts/coverage-truth.py`
- Create: `.github/coverage-exemptions.txt`
- Modify: `.github/workflows/lint.yml` (paperwork job, append one step)
- Create: `docs/superpowers/receipts/2026-08-20-tripwire-receipts.md`

**Interfaces:**

- Consumes: repo tree as-is (pre-fix — that is the point of the receipts).

- Produces: `python3 .github/scripts/coverage-truth.py` with contract
  **rc=0 PASS / rc=1 RED (each failing arm named + set differences) / rc=2 NOT MEASURED**
  (unreadable or empty input is never a pass). Five arms: `test-dir`, `matrix`,
  `dependabot`, `golangci`, `exemptions`. Exemption file format: one module name per line,
  `#` comments allowed; an exemption suppresses ONLY the absent-test-dir consequences
  (test-dir arm), never the terraform-ecosystem dependabot requirement; a stale exemption
  (module deleted, or module that has since grown `test/`) is itself RED.

- \[ \] **Step 0: Create the branch**

```bash
git checkout main && git pull && git checkout -b patrol/coverage-truth
```

(If the branch already exists with the spec/plan commits, `git checkout patrol/coverage-truth && git pull` instead.)

- \[ \] **Step 1: Write the tripwire script**

`.github/scripts/coverage-truth.py`, exactly:

```python
#!/usr/bin/env python3
"""coverage-truth: the module population, CI test matrix, dependabot config,
golangci workdirs, and the exemption list must all agree.

Verdicts:
  rc=0 PASS
  rc=1 RED           (every failing arm named, set differences listed)
  rc=2 NOT MEASURED  (an input could not be read/parsed, or a population was
                      empty where empty cannot be a clean run)
"""
import json
import os
import sys


def refuse(msg):
    print(f"NOT MEASURED - {msg}")
    sys.exit(2)


try:
    import yaml
except ImportError:
    refuse("PyYAML unavailable; install python3-yaml - do NOT read this as PASS")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_yaml(relpath):
    path = os.path.join(ROOT, relpath)
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
    except Exception as exc:  # noqa: BLE001 - any read/parse failure is a refusal
        refuse(f"cannot read/parse {relpath}: {exc}")
    if not data:
        refuse(f"{relpath} parsed empty")
    return data


# Populations ---------------------------------------------------------------
mdir = os.path.join(ROOT, "modules")
if not os.path.isdir(mdir):
    refuse("modules/ directory missing")
modules = sorted(
    d for d in os.listdir(mdir) if os.path.isdir(os.path.join(mdir, d))
)
if not modules:
    refuse("modules/ has no module dirs - an empty population is not a clean run")
testdirs = sorted(
    m for m in modules if os.path.isdir(os.path.join(mdir, m, "test"))
)

test_wf = load_yaml(".github/workflows/test.yml")
try:
    matrix = test_wf["jobs"]["terratest"]["strategy"]["matrix"]["project"]
except (KeyError, TypeError):
    matrix = None
if not matrix:
    refuse("test.yml: jobs.terratest.strategy.matrix.project missing or empty")

dbot = load_yaml(".github/dependabot.yml")
updates = dbot.get("updates")
if not updates:
    refuse("dependabot.yml: updates missing or empty")
tf_dirs = {u.get("directory") for u in updates if u.get("package-ecosystem") == "terraform"}
go_dirs = {u.get("directory") for u in updates if u.get("package-ecosystem") == "gomod"}
if not tf_dirs or not go_dirs:
    refuse("dependabot.yml: terraform or gomod entry set is empty")

lint_wf = load_yaml(".github/workflows/lint.yml")
try:
    workdirs = json.loads(lint_wf["jobs"]["lint"]["with"]["golangci_workdirs"])
except (KeyError, TypeError, json.JSONDecodeError) as exc:
    workdirs = None
if not workdirs:
    refuse("lint.yml: jobs.lint.with.golangci_workdirs missing/unparsable/empty")

expath = os.path.join(ROOT, ".github", "coverage-exemptions.txt")
if not os.path.isfile(expath):
    refuse(".github/coverage-exemptions.txt missing - deleting the allowlist is not a way to pass")
exempt = []
with open(expath) as f:
    for line in f:
        entry = line.split("#", 1)[0].strip()
        if entry:
            exempt.append(entry)

# Arms ----------------------------------------------------------------------
want_test_entries = {f"modules/{m}/test" for m in testdirs}
want_tf = {f"/modules/{m}" for m in modules}
want_go = {f"/modules/{m}/test" for m in testdirs}
have_matrix = set(matrix)
have_wd = set(workdirs)

arms = {
    "test-dir": [
        f"modules/{m} has no test/ dir and no exemption"
        for m in modules
        if m not in testdirs and m not in exempt
    ],
    "matrix": (
        [f"{e} has a test dir but is missing from the test.yml matrix"
         for e in sorted(want_test_entries - have_matrix)]
        + [f"{e} is in the matrix but has no test dir on disk"
           for e in sorted(have_matrix - want_test_entries)]
    ),
    "dependabot": (
        [f"{d} has no terraform dependabot entry" for d in sorted(want_tf - tf_dirs)]
        + [f"{d} is in dependabot(terraform) but not on disk"
           for d in sorted(tf_dirs - want_tf)]
        + [f"{d} has no gomod dependabot entry" for d in sorted(want_go - go_dirs)]
        + [f"{d} is in dependabot(gomod) but not on disk"
           for d in sorted(go_dirs - want_go)]
    ),
    "golangci": (
        [f"{e} has a test dir but is missing from golangci_workdirs"
         for e in sorted(want_test_entries - have_wd)]
        + [f"{e} is in golangci_workdirs but has no test dir on disk"
           for e in sorted(have_wd - want_test_entries)]
    ),
    "exemptions": (
        [f"exemption '{m}' names a module that does not exist"
         for m in exempt if m not in modules]
        + [f"exemption '{m}' is stale: the module has since grown a test dir"
           for m in exempt if m in testdirs]
    ),
}

# Verdict -------------------------------------------------------------------
red = False
for name in ("test-dir", "matrix", "dependabot", "golangci", "exemptions"):
    violations = arms[name]
    if violations:
        red = True
        print(f"ARM {name}: RED")
        for item in violations:
            print(f"  - {item}")
    else:
        print(f"ARM {name}: OK")

print(
    f"population: {len(modules)} modules, {len(testdirs)} test dirs, "
    f"{len(exempt)} exemptions"
)
if red:
    print("COVERAGE TRUTH: RED")
    sys.exit(1)
print("COVERAGE TRUTH: PASS")
sys.exit(0)
```

- \[ \] **Step 2: Create the (initially empty-of-entries) exemption file**

`.github/coverage-exemptions.txt`:

```text
# Coverage exemptions — one module name per line, '#' comments.
# An entry suppresses ONLY the "module has no test dir" arm. It does NOT
# suppress the terraform dependabot requirement. A stale entry (module gone,
# or module that has since grown a test dir) turns the exemptions arm RED.
# Every entry carries a date and a reason pointing at the work that retires it.
```

- \[ \] **Step 3: Run on the pre-fix tree — capture the natural RED receipt**

Run from repo root:
`python3 .github/scripts/coverage-truth.py > /tmp/receipt-natural.txt 2>&1; echo rc=$? >> /tmp/receipt-natural.txt`
(rc goes INTO the receipt file, measured without a pipe — same convention as Step 4.)
**This natural receipt is section 1 of `docs/superpowers/receipts/2026-08-20-tripwire-receipts.md`**
— do not leave it in /tmp. Expected: `rc=1`. Arms `test-dir` (efs-access, service), `matrix`
(notice-parameter-store missing), `dependabot` (4 terraform dirs + 2 gomod dirs missing)
must be RED; `golangci` and `exemptions` OK. If any expected-RED arm prints OK, STOP —
the script has the blindness Kitten vetoed; fix before proceeding.

- \[ \] **Step 4: Force every implemented sub-direction red individually (sabotage receipts)**

The invariant is per SUB-DIRECTION, not per arm name (Lilith's count: the five arms
implement 11 sub-directions; the natural receipt proves 4 — test-dir, matrix-missing,
dependabot-tf-missing, dependabot-gomod-missing). Every OTHER implemented branch gets its
own planted violation, one at a time, each reverted before the next (verify `git status`
clean between plants). The four "configured but not on disk" plants matter most: a future
module DELETION fires exactly those branches — a roster outliving the thing it names is
this repo's original disease, one layer up:

1. `golangci` arm: in `.github/workflows/lint.yml`, change the `golangci_workdirs` value by
   removing the substring `"modules/persistence/test",` (entry AND its trailing comma, keeping
   valid JSON — malformed JSON gives rc=2 NOT MEASURED, which is the WRONG receipt); run; expect
   `ARM golangci: RED` + rc=1 naming `modules/persistence/test`. Revert with
   `git checkout -- .github/workflows/lint.yml`.
1. `exemptions` arm (nonexistent module): temporarily add line `ghost-module` to
   `.github/coverage-exemptions.txt`; run; expect `ARM exemptions: RED`
   "names a module that does not exist". Revert.
1. `exemptions` arm (grew-a-test): temporarily add line `persistence`; run; expect
   `ARM exemptions: RED` "stale ... grown a test dir". Revert.
1. `matrix` arm, ghost direction: temporarily append `- modules/ghost/test` (10-space indent) to
   the `matrix.project` list in `.github/workflows/test.yml`; run; expect `ARM matrix: RED`
   "is in the matrix but has no test dir on disk". Revert.
1. `dependabot` arm, terraform-ghost: temporarily duplicate any terraform entry in
   `.github/dependabot.yml` and change its directory to `"/modules/ghost"`; run; expect
   `ARM dependabot: RED` "in dependabot(terraform) but not on disk". Revert.
1. `dependabot` arm, gomod-ghost: same duplication with a gomod entry, directory
   `"/modules/ghost/test"`; run; expect `ARM dependabot: RED` "in dependabot(gomod) but
   not on disk". Revert.
1. `golangci` arm, ghost direction: temporarily append `,"modules/ghost/test"` inside the
   `golangci_workdirs` JSON (before the closing `]`, keeping valid JSON); run; expect
   `ARM golangci: RED` "in golangci_workdirs but has no test dir on disk". Revert.
1. NOT MEASURED contract: run with the exemptions file renamed away; expect
   `NOT MEASURED` + rc=2, NOT a pass. Restore.

End state: 11 implemented sub-directions, 11 seen red (4 natural + 7 planted), plus the
rc=2 refusal control. The receipts doc lists them in this order.

Capture all outputs (with rc lines, measured WITHOUT a pipe:
`python3 ... > f 2>&1; echo rc=$? >> f`) into
`docs/superpowers/receipts/2026-08-20-tripwire-receipts.md` with a one-line header per
receipt. These are Kitten's sign-off receipts — per-arm forced red, not forced red overall.

- \[ \] **Step 5: Add the paperwork step**

In `.github/workflows/lint.yml`, `paperwork` job, append after the
"Template paperwork done?" step:

```yaml
      - name: "Coverage truth"
        run: python3 .github/scripts/coverage-truth.py
```

(Local-only reads; no new harden-runner endpoints needed. PyYAML on `ubuntu-latest` is an
assumption whose measurement is PR A's first CI run: if the step reds with
`NOT MEASURED - PyYAML unavailable`, add `pypi.org:443` + `files.pythonhosted.org:443` to the
paperwork allowlist and a `pip install pyyaml` step — do NOT weaken the rc=2 contract.)

- \[ \] **Step 6: Commit**

```bash
git add .github/scripts/coverage-truth.py .github/coverage-exemptions.txt .github/workflows/lint.yml docs/superpowers/receipts/
git commit -m "✅ ci: five-arm coverage tripwire with per-arm forced-red receipts"
```

### Task 2: Test matrix + SSM egress

**Files:**

- Modify: `.github/workflows/test.yml`

**Interfaces:**

- Consumes: nothing from other tasks (matrix entry for a test dir that already exists).

- Produces: matrix containing `modules/notice-parameter-store/test`; allowlist containing
  `ssm.us-east-1.amazonaws.com:443`.

- \[ \] **Step 1: Add matrix entry**

In the `matrix.project` list append (10-space indent, no quotes, matching existing style):

```yaml
          - modules/notice-parameter-store/test
```

- \[ \] **Step 2: Add SSM endpoint to harden-runner allowlist**

In the `allowed-endpoints:` block, insert alphabetically (after
`sns.us-east-1.amazonaws.com:443` line region; keep one endpoint per line):

```yaml
            ssm.us-east-1.amazonaws.com:443
```

Reason on the record: the NPS test polls `ssm.GetParameter` from the RUNNER; efs-access's
`data.aws_ssm_parameter.al2023` also resolves from the runner during plan. Without this the
first `GetParameter` dies against egress-policy block.

- \[ \] **Step 3: prettier check + commit**

```bash
npx prettier@3.3.3 --check .github/workflows/test.yml
git add .github/workflows/test.yml
git commit -m "👷 ci: run notice-parameter-store terratest; allow ssm egress"
```

### Task 3: dependabot coverage

**Files:**

- Modify: `.github/dependabot.yml`

**Interfaces:**

- Produces: terraform entries for `/modules/efs-access`, `/modules/notice-github`,
  `/modules/notice-parameter-store`, `/modules/service`; gomod entries for
  `/modules/notice-github/test`, `/modules/notice-parameter-store/test`,
  `/modules/efs-access/test`. (`/modules/service/test` arrives in PR B with the dir.)

- Note: the efs-access/test gomod entry lands in the SAME PR as the dir (Task 4) — safe,
  dependabot reads config only from the default branch post-merge.

- \[ \] **Step 1: Add four terraform entries**

Duplicate the existing terraform entry shape verbatim for each new directory — for
`/modules/efs-access` (repeat identically for `/modules/notice-github`,
`/modules/notice-parameter-store`, `/modules/service`):

```yaml
  - package-ecosystem: "terraform"
    directory: "/modules/efs-access"
    schedule:
      interval: "weekly"
    groups:
      terraform:
        update-types:
          - "minor"
          - "patch"
    commit-message:
      prefix: "⬆️ (deps-tf):"
    cooldown:
      default-days: 14
```

- \[ \] **Step 2: Add three gomod entries**

Same duplication from the existing gomod shape — for `/modules/notice-github/test`
(repeat for `/modules/notice-parameter-store/test`, `/modules/efs-access/test`):

```yaml
  - package-ecosystem: "gomod"
    directory: "/modules/notice-github/test"
    schedule:
      interval: "weekly"
    groups:
      test:
        update-types:
          - "major"
          - "minor"
          - "patch"
    commit-message:
      prefix: "⬆️ (deps-test):"
    cooldown:
      default-days: 14
```

- \[ \] **Step 3: prettier + commit**

```bash
npx prettier@3.3.3 --check .github/dependabot.yml
git add .github/dependabot.yml
git commit -m "⬆️ ci: dependabot covers every submodule and every test dir"
```

### Task 4: efs-access terratest

**Files:**

- Create: `modules/efs-access/test/examples_complete_test.go`
- Create: `modules/efs-access/test/go.mod` (+ generated `go.sum`)
- Create: `modules/efs-access/test/.golangci.yml` — copy
  `modules/persistence/test/.golangci.yml` **verbatim, no edits**: `local-prefixes` is the
  repo umbrella path by design (lint.yml's header documents it; all six existing copies are
  identical) and prefix-matching already covers this module.
- Modify: `.github/workflows/test.yml` (matrix += `modules/efs-access/test`)
- Modify: `.github/workflows/lint.yml` (`golangci_workdirs` += `"modules/efs-access/test"`)

**Interfaces:**

- Consumes: existing `modules/efs-access/examples/complete` (defaults:
  `efs_access_enabled=false`, `create_transfer_bucket=false`; outputs `instance_id`,
  `connect_command`, `mount_path`, `transfer_bucket`; wires `../../../persistence`).

- Produces: `TestDefaultsDisabled` passing in CI.

- \[ \] **Step 1: Write the test** (no red phase exists for an infra apply-test; the first
  honest execution is Step 4 against the sandbox)

⚠️ **The example references `../../../persistence` — copying only the module dir to temp
dangles that path. Copy the REPO ROOT** (`rootFolder = "../../../"`).

`modules/efs-access/test/examples_complete_test.go`:

```go
package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/random"
    "github.com/gruntwork-io/terratest/modules/terraform"
    test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestDefaultsDisabled(t *testing.T) {
    t.Parallel()

    // The example sources ../../../persistence, so the copied tree must be the
    // repo root or that relative path dangles in the temp dir.
    rootFolder := "../../../"
    terraformFolderRelativeToRoot := "modules/efs-access/examples/complete"

    tempTestFolder := test_structure.CopyTerraformFolderToTemp(
        t, rootFolder, terraformFolderRelativeToRoot,
    )

    rndns := random.UniqueId()

    terraformOptions := &terraform.Options{
        TerraformDir: tempTestFolder,
        Upgrade:      true,
        Vars: map[string]interface{}{
            "namespace": rndns,
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    outputs := terraform.OutputAll(t, terraformOptions)

    // Example defaults keep the instance and bucket off: those outputs must be
    // null/empty, while the mount_path passthrough must be a non-empty string.
    for _, key := range []string{"instance_id", "connect_command", "transfer_bucket"} {
        if v, ok := outputs[key]; ok && v != nil && v != "" {
            t.Errorf("output %q should be null with example defaults, got %#v", key, v)
        }
    }
    mp, ok := outputs["mount_path"].(string)
    if !ok || mp == "" {
        t.Errorf("output mount_path should be a non-empty string, got %#v", outputs["mount_path"])
    }
}
```

- \[ \] **Step 2: go.mod**

`modules/efs-access/test/go.mod` seed (then `go mod tidy` fills the rest):

```text
module github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/modules/efs-access/test

go 1.26.0

require (
    github.com/gruntwork-io/terratest v1.0.1
)
```

Run in `modules/efs-access/test/`: `go mod tidy` → produces go.sum. Then `go vet ./...`
Expected: clean compile (test not yet run — that's Step 4).

- \[ \] **Step 3: rosters**

test.yml matrix += `- modules/efs-access/test` (after the notice-parameter-store line from
Task 2). lint.yml `golangci_workdirs` value becomes:

```text
'["modules/launcher/test","modules/persistence/test","modules/dns-record/test","modules/notice-github/test","modules/notice-discord/test","modules/notice-parameter-store/test","modules/efs-access/test"]'
```

- \[ \] **Step 4: First execution against the sandbox**

```bash
cd modules/efs-access/test
AWS_PROFILE=brd-sndbx-ue1-core-bendoerr go test -timeout 20m -v ./... 2>&1 | tee /tmp/efs-access-test.out
```

Expected: PASS (apply → asserts → destroy). If the destroy of EFS mount targets is slow
that is known-sulky; only a FAILED destroy is a defect. On assert failures: fix the test's
expectations against measured outputs, not the module.

- \[ \] **Step 5: Commit**

```bash
git add modules/efs-access/test .github/workflows/test.yml .github/workflows/lint.yml
git commit -m "✅ (efs-access): terratest for the cost-safe example defaults"
```

### Task 5: notice-parameter-store test modernization (fix-forward)

**Files:**

- Modify: `modules/notice-parameter-store/test/go.mod` (+ go.sum)
- Modify: `modules/notice-parameter-store/test/examples_complete_test.go` (timeout only)

**Interfaces:**

- Consumes: the existing test (SNS publish → Lambda → SSM parameter round-trip poll).

- Produces: test compiling on terratest v1.0.1 / go 1.26.0 and passing locally.

- \[ \] **Step 1: Bump the toolchain and deps**

In `modules/notice-parameter-store/test/`:

```bash
go mod edit -go=1.26.0
go get github.com/gruntwork-io/terratest@v1.0.1 \
       github.com/aws/aws-sdk-go-v2/config@v1.32.34 \
       github.com/aws/aws-sdk-go-v2/service/sns@latest \
       github.com/aws/aws-sdk-go-v2/service/ssm@latest
go mod tidy
go vet ./...
```

Expected: clean. terratest 0.47→1.0.1 drops the aws-sdk-go v1 / GCP / OTel tree; the APIs
this test uses (`terraform.Options`, `InitAndApply`, `Destroy`, `OutputAll`,
`random.UniqueId`, `test_structure.CopyTerraformFolderToTemp`) are stable across the bump.
If `go vet` reports a removed symbol, fix the call site to the v1.0.1 name — do not pin
back to 0.47.

- \[ \] **Step 2: Widen the propagation window**

In `examples_complete_test.go:101`, the poll loop bounds SNS→Lambda→SSM propagation with
`timeoutTimer := time.After(time.Second * 10)`. A cold Lambda start alone can eat that.
Change **only the bound**: `time.After(time.Second * 10)` → `time.After(time.Second * 60)`
(keep the 1s sleep per iteration). The assertion itself (exact JSON round-trip) is untouched.

- \[ \] **Step 3: Run locally against the sandbox**

```bash
cd modules/notice-parameter-store/test
AWS_PROFILE=brd-sndbx-ue1-core-bendoerr go test -timeout 20m -v ./... 2>&1 | tee /tmp/nps-test.out
```

Expected: PASS. This is the first execution of this test in recorded history — treat any
failure as ROT TO FIX (in the test or its example), and record what was found in the PR
body. Known drift already measured: null-label ref `v0.4.1` in its example ctx.tf (leave —
works), `environment = "test"` vs house `"testing"` (leave — cosmetic).

- \[ \] **Step 4: Commit**

```bash
git add modules/notice-parameter-store/test
git commit -m "⬆️ (notice-parameter-store): modernize never-run test to terratest v1.0.1; widen propagation window"
```

### Task 6: The service exemption + green receipt + PR A

**Files:**

- Modify: `.github/coverage-exemptions.txt`

- Modify: `docs/superpowers/receipts/2026-08-20-tripwire-receipts.md` (append green receipt)

- \[ \] **Step 1: Add the dated exemption**

Append to `.github/coverage-exemptions.txt`:

```text
service  # 2026-08-20 example+test land in PR B (patrol/service-coverage); entry dies there. If PR B is abandoned, this line is the debt record.
```

- \[ \] **Step 2: Green receipt**

`python3 .github/scripts/coverage-truth.py > /tmp/receipt-green.txt 2>&1; echo rc=$? >> /tmp/receipt-green.txt`
Expected: all five arms OK, `COVERAGE TRUTH: PASS`, rc=0, population line
`8 modules, 7 test dirs, 1 exemptions`. Append to the receipts doc.

- \[ \] **Step 3: Commit, push, open PR A**

```bash
git add .github/coverage-exemptions.txt docs/superpowers/receipts/
git commit -m "🔧 ci: dated service exemption until PR B; tripwire green receipt"
git push -u origin patrol/coverage-truth
```

Open the PR with `gh pr create` — title
`✅ ci: coverage truth — tripwire, full dependabot/matrix rosters, efs-access + notice-parameter-store tests`,
body: problem table from the spec, the receipts file link, wall-clock note (+25–35 min),
and the PR B forward-reference. Then the patrol arc's review gates take over (CI watch,
/review ×2, Kitten sign-off, merge per Hard Rule #1 — my PR, my button after his APPROVE).

______________________________________________________________________

## PR B — branch `patrol/service-coverage` (created from main AFTER PR A merges)

### Task 7: service example (parked at zero)

**Files:**

- Precondition gate (Step 0): PR A verified MERGED before any work.
- Create: `modules/service/examples/complete/ctx.tf`
- Create: `modules/service/examples/complete/versions.tf`
- Create: `modules/service/examples/complete/vpc.tf`
- Create: `modules/service/examples/complete/service_complete.tf`

**Interfaces:**

- Consumes: `modules/service` (all REQUIRED vars listed below get values),
  `modules/persistence` (EFS id/access-point/policy/SG outputs),
  `modules/dns-record` (`create_zone=true` → `zone_id`, `record_name`,
  `record_control_policy_arn`).
- Produces: outputs `ecs_cluster_name`, `ecs_service_name`, `events_topic_arn`,
  `service_role_name`, `svc_control_policy_arn` (mapping the module's `esc_*`-typo'd
  outputs to clean names — do NOT rename the module outputs; that's a breaking change).

Gotchas this example exists to satisfy (all measured):
`record_control_policy_arn` and `persistence_access_security_group` are consumed
UNCONDITIONALLY — empty strings fail apply, so real values come from dns-record and
persistence. `enable_container_insights`, `logs_kms_key_id`, `sns_kms_key_id` have NO
defaults — pass `false`, `null`, `null`. `task_cpu`/`task_memory` are STRINGS
(`"256"`/`"512"`), unlike the upstream registry module launcher's example uses.
`desired_count = 0` is hardcoded in the module with `ignore_changes` — zero Fargate
compute by construction. The watchdog sidecar image is never pulled at desired 0.

- \[ \] **Step 0: Verify PR A merged, create the branch**

```bash
gh pr view patrol/coverage-truth -R bendoerr-terraform-modules/terraform-aws-fargate-on-demand --json state,mergeCommit
```

Expected: `"state": "MERGED"` with a non-empty mergeCommit. If not MERGED, STOP — PR B
built on a pre-tripwire tree makes Task 9's receipts lie. Then:

```bash
git checkout main && git pull && git checkout -b patrol/service-coverage
```

- \[ \] **Step 1: ctx.tf** (house pattern)

```hcl
variable "namespace" {
  type = string
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.4.0"
  namespace   = var.namespace
  environment = "testing"
  role        = "development"
  region      = "us-east-1"
  project     = "service"
}
```

- \[ \] **Step 2: versions.tf** — ⚠️ floor is 1.9.0 here, NOT the house 1.3.0
  (`modules/service/versions.tf` demands `>= 1.9.0` for cross-variable validation):

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = "us-east-1"
}
```

- \[ \] **Step 3: vpc.tf** — the house version, exactly:

```hcl
module "label_network" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "ntwrk"
}

module "vpc" {
  source     = "terraform-aws-modules/vpc/aws"
  version    = "5.1.1"
  create_vpc = true

  name = module.label_network.id

  cidr           = "10.10.0.0/16"
  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.10.1.0/24", "10.10.2.0/24"]

  enable_nat_gateway = false
}
```

- \[ \] **Step 4: service_complete.tf**

```hcl
module "fod_dns_record" {
  source  = "../../../dns-record"
  context = module.context.shared

  create_zone = true
  zone_name   = "${lower(var.namespace)}.fod-svc.test"
  record_name = "play.${lower(var.namespace)}.fod-svc.test"
}

module "fod_persistence" {
  source     = "../../../persistence"
  context    = module.context.shared
  subnet_ids = module.vpc.public_subnets
}

module "fod_service" {
  source  = "../.."
  context = module.context.shared

  vpc_id             = module.vpc.vpc_id
  service_subnet_ids = module.vpc.public_subnets

  task_cpu    = "256"
  task_memory = "512"

  service_image = "public.ecr.aws/docker/library/alpine:3"

  port_mappings = [
    {
      containerPort = 25565
      hostPort      = 25565
      protocol      = "tcp"
    },
  ]

  environment_variables = []
  secret_variables      = []

  dns_zone_id               = module.fod_dns_record.zone_id
  dns_record                = module.fod_dns_record.record_name
  record_control_policy_arn = module.fod_dns_record.record_control_policy_arn

  data_file_system_id               = module.fod_persistence.file_system_id
  data_access_point_id              = module.fod_persistence.access_point_id
  persistence_access_policy_arn     = module.fod_persistence.access_policy_arn
  persistence_access_security_group = module.fod_persistence.access_security_group

  enable_container_insights = false
  logs_kms_key_id           = null
  sns_kms_key_id            = null
}

output "ecs_cluster_name" {
  value       = module.fod_service.esc_cluster_name
  description = "Name of the ECS cluster."
}

output "ecs_service_name" {
  value       = module.fod_service.esc_service_name
  description = "Name of the ECS service (parked at desired count 0)."
}

output "events_topic_arn" {
  value       = module.fod_service.events_topic_arn
  description = "SNS topic the watchdog publishes lifecycle events to."
}

output "service_role_name" {
  value       = module.fod_service.service_role_name
  description = "Name of the combined task + execution role."
}

output "svc_control_policy_arn" {
  value       = module.fod_service.svc_control_policy_arn
  description = "IAM policy that allows the launcher to control this service."
}
```

- \[ \] **Step 5: Validate + commit**

```bash
cd modules/service/examples/complete && terraform init -backend=false && terraform validate
git add modules/service/examples/
git commit -m "✨ (service): runnable example parked at desired-count zero"
```

(Route53 note for the record: a hosted zone deleted within hours is inside AWS's
same-12-hours no-charge window; the test's defer-destroy removes it in minutes.)

### Task 8: service terratest

**Files:**

- Create: `modules/service/test/examples_complete_test.go`
- Create: `modules/service/test/go.mod` (+ tidy → go.sum)
- Create: `modules/service/test/.golangci.yml` — copy
  `modules/persistence/test/.golangci.yml` **verbatim, no edits** (`local-prefixes` is the
  repo umbrella path by design; all existing copies are identical).

**Interfaces:**

- Consumes: Task 7's outputs by exact name.

- Produces: `TestServiceParkedAtZero` — Kitten's Q3 contract: cluster+service exist,
  desired=0, taskdef ACTIVE, IAM role assumable by ecs-tasks, SNS topic wired, launcher
  control policy real.

- \[ \] **Step 1: go.mod seed** (then `go mod tidy` — it adds the ecs/iam/sns service
  clients as direct requires at whatever versions co-resolve; do NOT hand-pin them)

```text
module github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/modules/service/test

go 1.26.0

require (
    github.com/aws/aws-sdk-go-v2/config v1.32.34
    github.com/gruntwork-io/terratest v1.0.1
)
```

- \[ \] **Step 2: the test**

```go
package test

import (
    "context"
    "net/url"
    "strings"
    "testing"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/ecs"
    "github.com/aws/aws-sdk-go-v2/service/iam"
    "github.com/aws/aws-sdk-go-v2/service/sns"
    "github.com/gruntwork-io/terratest/modules/random"
    "github.com/gruntwork-io/terratest/modules/terraform"
    test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestServiceParkedAtZero(t *testing.T) {
    t.Parallel()

    // The example sources ../../../dns-record and ../../../persistence, so the
    // copied tree must be the repo root or those relative paths dangle.
    rootFolder := "../../../"
    terraformFolderRelativeToRoot := "modules/service/examples/complete"

    tempTestFolder := test_structure.CopyTerraformFolderToTemp(
        t, rootFolder, terraformFolderRelativeToRoot,
    )

    // Lowercased: the namespace feeds a DNS zone name in the example.
    rndns := strings.ToLower(random.UniqueId())

    terraformOptions := &terraform.Options{
        TerraformDir: tempTestFolder,
        Upgrade:      true,
        Vars: map[string]interface{}{
            "namespace": rndns,
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    clusterName := terraform.Output(t, terraformOptions, "ecs_cluster_name")
    serviceName := terraform.Output(t, terraformOptions, "ecs_service_name")
    topicArn := terraform.Output(t, terraformOptions, "events_topic_arn")
    roleName := terraform.Output(t, terraformOptions, "service_role_name")
    controlPolicyArn := terraform.Output(t, terraformOptions, "svc_control_policy_arn")

    cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("us-east-1"))
    if err != nil {
        t.Fatal(err)
    }

    // Service exists on the module's cluster, ACTIVE, parked at zero.
    ecsClient := ecs.NewFromConfig(cfg)
    svcOut, err := ecsClient.DescribeServices(context.TODO(), &ecs.DescribeServicesInput{
        Cluster:  aws.String(clusterName),
        Services: []string{serviceName},
    })
    if err != nil {
        t.Fatal(err)
    }
    if len(svcOut.Services) != 1 {
        t.Fatalf("expected exactly 1 service, got %d", len(svcOut.Services))
    }
    svc := svcOut.Services[0]
    if aws.ToString(svc.Status) != "ACTIVE" {
        t.Errorf("service status should be ACTIVE, got %q", aws.ToString(svc.Status))
    }
    if svc.DesiredCount != 0 {
        t.Errorf("desired count should be 0 (scale-to-zero is the native state), got %d", svc.DesiredCount)
    }

    // The registered task definition is ACTIVE.
    tdOut, err := ecsClient.DescribeTaskDefinition(context.TODO(), &ecs.DescribeTaskDefinitionInput{
        TaskDefinition: svc.TaskDefinition,
    })
    if err != nil {
        t.Fatal(err)
    }
    if string(tdOut.TaskDefinition.Status) != "ACTIVE" {
        t.Errorf("task definition status should be ACTIVE, got %q", tdOut.TaskDefinition.Status)
    }

    // The task role trusts ecs-tasks.amazonaws.com.
    iamClient := iam.NewFromConfig(cfg)
    role, err := iamClient.GetRole(context.TODO(), &iam.GetRoleInput{RoleName: aws.String(roleName)})
    if err != nil {
        t.Fatal(err)
    }
    doc, err := url.QueryUnescape(aws.ToString(role.Role.AssumeRolePolicyDocument))
    if err != nil {
        t.Fatal(err)
    }
    if !strings.Contains(doc, "ecs-tasks.amazonaws.com") {
        t.Errorf("assume-role policy does not trust ecs-tasks.amazonaws.com: %s", doc)
    }

    // The launcher-control policy the module exports is a real, reachable policy.
    _, err = iamClient.GetPolicy(context.TODO(), &iam.GetPolicyInput{
        PolicyArn: aws.String(controlPolicyArn),
    })
    if err != nil {
        t.Errorf("svc control policy not reachable: %v", err)
    }

    // The events topic is real and reachable.
    snsClient := sns.NewFromConfig(cfg)
    _, err = snsClient.GetTopicAttributes(context.TODO(), &sns.GetTopicAttributesInput{
        TopicArn: aws.String(topicArn),
    })
    if err != nil {
        t.Errorf("events topic not reachable: %v", err)
    }
}
```

- \[ \] **Step 3: `go mod tidy && go vet ./...`** — expected clean.

- \[ \] **Step 4: Run locally against the sandbox**

```bash
cd modules/service/test
AWS_PROFILE=brd-sndbx-ue1-core-bendoerr go test -timeout 20m -v ./... 2>&1 | tee /tmp/service-test.out
```

Expected: PASS with zero Fargate tasks launched. Any apply failure inside
`modules/service` itself is a REAL module bug this test just found — report it in the PR,
fix only if contained (a validation/typo class); anything behavioral escalates to a
design conversation, not a silent patch.

- \[ \] **Step 5: Commit**

```bash
git add modules/service/test
git commit -m "✅ (service): terratest — cluster/service/taskdef/IAM/SNS asserted at desired-count zero"
```

### Task 9: Retire the exemption; rosters pick up service

**Files:**

- Modify: `.github/workflows/test.yml` (matrix += `modules/service/test`)

- Modify: `.github/workflows/lint.yml` (`golangci_workdirs` += `"modules/service/test"`)

- Modify: `.github/dependabot.yml` (gomod += `/modules/service/test`, same shape as Task 3 Step 2)

- Modify: `.github/coverage-exemptions.txt` (delete the `service` line — comments stay)

- \[ \] **Step 1: All four edits, verbatim**

1. `.github/workflows/test.yml` — append to the `matrix.project` list (10-space indent,
   no quotes):

```yaml
          - modules/service/test
```

1. `.github/workflows/lint.yml` — `golangci_workdirs` becomes (single-line JSON string,
   single-quoted):

```text
'["modules/launcher/test","modules/persistence/test","modules/dns-record/test","modules/notice-github/test","modules/notice-discord/test","modules/notice-parameter-store/test","modules/efs-access/test","modules/service/test"]'
```

1. `.github/dependabot.yml` — append this gomod entry:

```yaml
  - package-ecosystem: "gomod"
    directory: "/modules/service/test"
    schedule:
      interval: "weekly"
    groups:
      test:
        update-types:
          - "major"
          - "minor"
          - "patch"
    commit-message:
      prefix: "⬆️ (deps-test):"
    cooldown:
      default-days: 14
```

1. `.github/coverage-exemptions.txt` — delete the line starting `service` (the header
   comments stay; the file must continue to exist even entry-less — the tripwire refuses
   rc=2 if it is missing).

- \[ \] **Step 2: Tripwire green with EMPTY allowlist — the patrol's closing receipt**

`python3 .github/scripts/coverage-truth.py` → expected: five arms OK,
`population: 8 modules, 8 test dirs, 0 exemptions`, rc=0. Append receipt to the receipts
doc (this file rides PR B).

- \[ \] **Step 3: prettier + commit + push + PR B**

```bash
npx prettier@3.3.3 --check .github/workflows/test.yml .github/workflows/lint.yml .github/dependabot.yml
git add .github/ docs/superpowers/receipts/
git commit -m "✅ ci: service coverage complete; exemption list empty"
git push -u origin patrol/service-coverage
```

Open PR B; arc gates as usual.

______________________________________________________________________

## Post-ship (not part of either PR)

### Task 10: The dated Q2 follow-up + the standing recon step

- \[ \] **Step 1:** `gh issue create` on the repo: title
  `✨ (efs-access): enabled=true terratest pass (real instance path)`, body states the
  defaults-only decision (family brainstorm 2026-08-20), the flake-surface reasoning, a
  separate-test-func + own-defer requirement, and **re-check date 2026-11-20** — plus the
  rule that any patrol touching this repo re-reads open follow-up issues first.
- \[ \] **Step 2:** In `~/omyac`, edit `.claude/skills/renovation-patrol/SKILL.md`: in the
  recon guidance (before step 2 of the arc), add one sentence: *"Recon includes re-reading
  open follow-up issues filed by prior patrols (`gh issue list --author @me` across the
  org + working repos) — a follow-up only exists if something re-reads it."* Commit to
  omyac per the every-trigger contract.
