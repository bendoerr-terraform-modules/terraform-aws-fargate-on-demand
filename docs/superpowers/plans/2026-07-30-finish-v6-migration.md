# Finish the fargate-on-demand v6 migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `terraform-aws-fargate-on-demand` tell the truth about what Terraform it requires and what it does — floors, generated docs, README prose, and a CI receipt that keeps them honest.

**Architecture:** The AWS provider was bumped v5→v6 (`aws ~> 6.x` everywhere) but the migration was never finished: `required_version` floors, terraform-docs tables, and the README lag behind. Fix the floors to one truthful org standard, add a CI leg that makes each floor executable truth, regenerate the stale docs, and write the README prose that ships as literal `TODO` on the public Registry.

**Tech Stack:** Terraform (HCL), terraform-docs, GitHub Actions, terratest (existing, untouched).

**Repo:** `bendoerr-terraform-modules/terraform-aws-fargate-on-demand`
**Branch:** `renovation/finish-v6-migration`
**Reviewer/gate:** code-kitten (plan + PR). Release/tag gate: kitten + Lilith.

## Global Constraints

- **Working paths (absolute, no guessing):** scratchpad = `/tmp/claude-1001/-home-ombb-omyac/9ea1bd85-ed21-4a2d-9cf8-0347e52637b1/scratchpad`; repo clone = `$SCRATCH/fargate-reno`. Every step below assumes `SCRATCH=/tmp/claude-1001/-home-ombb-omyac/9ea1bd85-ed21-4a2d-9cf8-0347e52637b1/scratchpad` and `REPO=$SCRATCH/fargate-reno`.
- **Floor standard (verbatim):** *Modules declare `required_version = ">= 1.3.0"`, floors only, never `~>`.* Upper caps (`~>`, `<`) belong to root modules, never reusable modules.
- **Rationale (accurate for THIS repo):** `>= 1.3.0` is a deliberate ORG-WIDE POLICY baseline (1.3.0 is the floor of the org's pattern language — where the `optional()` context/label idiom lives ACROSS the org). NOTE: this specific repo has ZERO `optional()` usage (verified) and no code feature above TF 1.0 except `service`'s cross-var validation — so this repo's hard code-driven minimum is 1.0 (aws provider v6). We adopt 1.3.0 anyway as the org standard for consistency. Commit bodies must say "adopt org baseline >= 1.3.0 (policy floor; this repo's hard minimum is 1.0)" — do NOT claim this repo uses `optional()`.
- **Survivor deviations** (floor above 1.3.0) are allowed ONLY with a one-line greppable receipt comment on the `required_version` line: `# floor-reason: <feature> requires Terraform <x.y>`. Baseline (1.3.0) modules carry NO comment. Any floor >1.3.0 lacking `floor-reason:` is an audit failure by definition.
- **Confirmed survivor:** `modules/service` = `>= 1.9.0` — `task_memory`'s validation condition references `var.task_cpu` (cross-variable validation, TF 1.9). This is the ONLY survivor; every other module has no cross-var validation and no `optional()`.
- **terraform-docs regeneration** must match the existing table format EXACTLY (marker-wrapped `<!-- BEGIN_TF_DOCS -->`…`<!-- END_TF_DOCS -->`). Diff must show only truth changes, never format churn.
- **CI scope:** the new floor-check leg is IN (it is the floor change's *receipt*, ruled not a Hard-Rule-#4 violation by both gates). Workflow *parity* (codeql/pr-label/scorecard) is OUT (Ben policy call). No existing workflow pins TF below the floor (`setup-terraform` is unpinned=latest) — nothing to fix there.
- **Hard rules:** never commit secrets; never `git push --force`; throttle GitHub writes; conventional/gitmoji commit messages per org convention.

## File Structure (what changes)

- `modules/*/versions.tf` (8) + `modules/*/examples/**/versions.tf` + `modules/*/examples/**/ctx.tf` — `required_version` floors. (Task 1)
- `.github/workflows/floor-check.yml` — NEW. Matrix `init -backend=false && validate` pinned to each module's exact floor + a `convention` self-policing grep job. (Task 2)
- `.terraform-docs.yml` — NEW (repo root). Pins terraform-docs format so regens are reproducible. (Task 3)
- `modules/launcher/README.md`, `modules/dns-record/README.md`, `modules/efs-access/README.md` — regenerate marker-wrapped terraform-docs sections against the pinned config. (Task 3)
- `README.md` (root) — Usage code block (real example) + replace six empty terraform-docs data-section TODOs with a real `## Modules` index. About + Version Constraints ALREADY real prose, untouched. (Task 4)
- **Root README and submodule READMEs are owned by different tasks (4 vs 3) with NO file overlap** — root has no terraform-docs markers/`.tf`.

---

### Task 1: Truthful, consistent version floors

**Files:**
- Modify: every `modules/*/versions.tf` and every `modules/*/examples/**/versions.tf` and `modules/*/examples/**/ctx.tf` that declares `required_version`.
- Verify tooling: download Terraform 1.3.0 + 1.9.0 to scratchpad for the local floor proof.

**Floor assignment (final):**
| module | current | → target | note |
|---|---|---|---|
| dns-record | `~> 1.0` | `>= 1.3.0` | kill the cap shape |
| efs-access | `>= 0.13` | `>= 1.3.0` | |
| launcher | `~> 1.0` | `>= 1.3.0` | kill the cap shape |
| notice-discord | `>= 0.13` | `>= 1.3.0` | |
| notice-github | `>= 0.13` | `>= 1.3.0` | |
| notice-parameter-store | `>= 0.13` | `>= 1.3.0` | |
| persistence | `>= 0.13` | `>= 1.3.0` | |
| service | `>= 1.9` | `>= 1.9.0` + `# floor-reason:` | KEEP — cross-var validation |
| all `examples/**` | `>= 0.13` | `>= 1.3.0` | demonstrate baseline |

- [ ] **Step 1: Install pinned Terraform binaries for the local proof**
```bash
SCRATCH=/tmp/claude-1001/-home-ombb-omyac/9ea1bd85-ed21-4a2d-9cf8-0347e52637b1/scratchpad
REPO=$SCRATCH/fargate-reno
cd "$SCRATCH"
for v in 1.3.0 1.9.0; do
  curl -sSL -o tf_$v.zip https://releases.hashicorp.com/terraform/$v/terraform_${v}_linux_amd64.zip
  mkdir -p tfbin/$v && (cd tfbin/$v && unzip -oq ../../tf_$v.zip)
done
"$SCRATCH/tfbin/1.3.0/terraform" version   # expect Terraform v1.3.0
```

- [ ] **Step 2: Configure local git rewrite so `terraform init` can fetch the SSH module sources over https**
`terraform-null-label` and `terraform-null-context` are both PUBLIC (verified) — plain https, no token needed:
```bash
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

- [ ] **Step 3: Edit every floor per the table.** In each `versions.tf`/`ctx.tf`, set `required_version = ">= 1.3.0"` (no `~>`, no cap). For `modules/service/versions.tf` ONLY:
```hcl
required_version = ">= 1.9.0" # floor-reason: cross-variable validation (var.task_memory references var.task_cpu) requires Terraform 1.9
```

- [ ] **Step 4: Format check**
```bash
cd "$REPO" && terraform fmt -recursive -check
```
Expected: exit 0 (no diff). If it reformats, `terraform fmt -recursive` then re-run `-check`.

- [ ] **Step 5: Prove every floor is executable truth (local, the same check CI will run in Task 2)**
```bash
cd "$REPO"
# baseline modules on 1.3.0
for m in dns-record efs-access launcher notice-discord notice-github notice-parameter-store persistence; do
  (cd modules/$m && rm -rf .terraform && "$SCRATCH/tfbin/1.3.0/terraform" init -backend=false -input=false && "$SCRATCH/tfbin/1.3.0/terraform" validate) || echo "FAILED: $m"
done
# survivor on 1.9.0
(cd modules/service && rm -rf .terraform && "$SCRATCH/tfbin/1.9.0/terraform" init -backend=false -input=false && "$SCRATCH/tfbin/1.9.0/terraform" validate) || echo "FAILED: service"
```
Expected: every module prints `Success! The configuration is valid.` on its pinned floor.
**Triage a FAILED module by reading the actual error** ([[feedback-verify-failure-log]]):
- error mentions `Unsupported Terraform Core version` / `required_version` → genuine floor lie: the module's true (possibly transitive, via a null-label ref) minimum is higher. Raise that module's floor to the real minimum + add a `# floor-reason:` comment naming the cause. Do NOT paper over it.
- error mentions module download / git / network / `Failed to download` → a FETCH problem, NOT a floor problem. Fix the fetch (Step 2 rewrite) and re-run. Do NOT raise the floor.

- [ ] **Step 6: Confirm no lies remain**
```bash
grep -rn 'required_version' --include='*.tf' . | grep -E '0\.13|~>' && echo "STILL LYING" || echo "clean"
grep -rn 'required_version = ">= 1.9' --include='*.tf' . | grep -v 'floor-reason' && echo "UNDOCUMENTED HIGH FLOOR" || echo "receipts present"
```
Expected: `clean` and `receipts present`.

- [ ] **Step 7: Commit**
```bash
git add -A
git commit -m "🔧 fix: truthful Terraform version floors (>= 1.3.0 baseline; service keeps 1.9)

The aws v5->v6 bump left required_version behind. Most modules declared
>= 0.13, which cannot init the v6 provider (needs TF >= 1.0). Adopt the org
baseline >= 1.3.0 (a deliberate policy floor; this repo's hard minimum is 1.0
via the v6 provider), floors only, no ~> caps. service keeps >= 1.9.0 for
cross-variable validation (task_memory validated against task_cpu), with a
greppable floor-reason receipt."
```

---

### Task 2: CI floor-check leg (the receipt / drift-guard)

**Files:**
- Create: `.github/workflows/floor-check.yml`

**Interfaces:**
- Consumes: the floors set in Task 1 (matrix pins to them).
- Produces: a required-ish PR check proving each module inits+validates on its exact declared floor.

**Rationale (record in commit body):** the bug was *drift* — code moved, floor didn't. A comment can't detect re-drift; an executable check can. init pinned to the exact floor also enforces transitive floors (a child-module ref needing >floor fails loudly). Both gates ruled this is the floor change's receipt, not workflow renovation → not a Hard-Rule-#4 violation.

**Why two CI legs (verbatim, for the commit/PR body):** *terratest on unpinned-latest above, pin-to-floor validate below — the supported range bracketed at both ends, floor proven, ceiling tracked.*

- [ ] **Step 1: Write the workflow**
```yaml
name: Floor Check

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]

permissions:
  contents: read

jobs:
  floor:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - { module: modules/dns-record,             tf: "1.3.0" }
          - { module: modules/efs-access,             tf: "1.3.0" }
          - { module: modules/launcher,               tf: "1.3.0" }
          - { module: modules/notice-discord,         tf: "1.3.0" }
          - { module: modules/notice-github,          tf: "1.3.0" }
          - { module: modules/notice-parameter-store, tf: "1.3.0" }
          - { module: modules/persistence,            tf: "1.3.0" }
          - { module: modules/service,                tf: "1.9.0" }
    steps:
      - name: "Harden Runner"
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            checkpoint-api.hashicorp.com:443
            github.com:22
            github.com:443
            objects.githubusercontent.com:443
            raw.githubusercontent.com:443
            registry.terraform.io:443
            release-assets.githubusercontent.com:443
            releases.hashicorp.com:443
      - name: "Checkout"
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - name: "Setup Terraform (pinned to declared floor)"
        uses: step-security/setup-terraform@11f45fe036ccfd27d231861d38b183d405b059a9 # v4.0.0
        with:
          terraform_version: ${{ matrix.tf }}
          terraform_wrapper: false
      - name: "Setup SSH Agent (module fetch)"
        uses: step-security/ssh-agent@04004923389ca1b759b2bee0005f2db1253aeb15 # v0.10.0
        with:
          ssh-private-key: |
            ${{ secrets.ORG_ACCESS_SSH_KEY }}
      - name: "Init + validate at exact floor"
        working-directory: ${{ matrix.module }}
        run: |
          terraform init -backend=false -input=false
          terraform validate

  convention:
    runs-on: ubuntu-latest
    steps:
      - name: "Harden Runner"
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: block
          allowed-endpoints: >
            github.com:443
      - name: "Checkout"
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - name: "Floors self-police: baseline silent, deviations documented"
        run: |
          set -euo pipefail
          # Every required_version must be exactly the ">= 1.3.0" baseline OR carry a
          # "# floor-reason:" receipt. This one assertion subsumes "no >= 0.13" and
          # "no ~> caps" (those lines are neither baseline nor receipted) and makes the
          # convention executable instead of a rule that lives in a Discord scroll.
          bad=$(grep -rn 'required_version' --include='*.tf' . \
            | grep -vE 'required_version += +">= 1\.3\.0"' \
            | grep -v 'floor-reason:' || true)
          if [ -n "$bad" ]; then
            echo "::error::each required_version must be '>= 1.3.0' (baseline) or carry a '# floor-reason:' receipt"
            echo "$bad"
            exit 1
          fi
          echo "floors: baseline silent, deviations documented ✓"
```
Note: SHA-pin the actions to the SAME SHAs already used in `test.yml` (copied above — verify they still match at execution time). Confirm `step-security/setup-terraform@v4` accepts `terraform_version` (it is a drop-in fork of hashicorp/setup-terraform, which does).

- [ ] **Step 2: Lint the workflow**
```bash
# actionlint if available; else yaml parse
actionlint .github/workflows/floor-check.yml || python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/floor-check.yml'))"
```
Expected: no errors.

- [ ] **Step 3: Commit**
```bash
git add .github/workflows/floor-check.yml
git commit -m "🔧 ci: add floor-check — init+validate each module at its exact required_version

Makes the version floor executable truth instead of a comment: the bug we
just fixed was drift (code moved, floor didn't), and only a check pinned to
the exact floor catches re-drift + transitive floor lies. Additive receipt
for the floor change; no cloud creds (validate needs none)."
```
(Real proof: this runs when the PR opens. If a module fails, treat as Task-1 Step-5 fallback — raise the true floor.)

---

### Task 3: Regenerate submodule terraform-docs — pin format, kill stale v5 rows

**Files:**
- Create: `.terraform-docs.yml` (repo root) — pins the format so regens are reproducible (anti-drift symmetry with the floor-check).
- Modify: `modules/launcher/README.md`, `modules/dns-record/README.md`, `modules/efs-access/README.md` (marker-wrapped sections ONLY).
- **Root `README.md` is NOT touched here** — it has no terraform-docs markers and no `.tf`; it belongs entirely to Task 4.

**Interfaces:**
- Consumes: floors from Task 1 (the `terraform` Requirements row must reflect the new floor: `>= 1.3.0` for launcher/dns-record/efs-access).

**Reality this task must handle (verified):** the three target READMEs are in TWO different terraform-docs formats — `efs-access` is column-**padded/aligned** and already `aws ~> 6.32` (only its `terraform >= 0.13` row is stale); `launcher` + `dns-record` are **compact/unpadded** and still advertise `aws ~> 5.0` / provider `5.25.0`. There is no `.terraform-docs.yml`. A single regen CANNOT reproduce both formats, so a one-time normalization to ONE pinned format is unavoidable and intentional. The verification below proves the *content* diff is truth-only even though *whitespace/alignment* changes.

- [ ] **Step 1: Install terraform-docs (not on box), pinned**
```bash
cd "$SCRATCH"
curl -sSLo tfdocs.tar.gz https://terraform-docs.io/dl/v0.20.0/terraform-docs-v0.20.0-linux-amd64.tar.gz
tar xzf tfdocs.tar.gz terraform-docs && chmod +x terraform-docs && ./terraform-docs --version   # expect v0.20.0
```

- [ ] **Step 2: Create `.terraform-docs.yml` matching the freshest existing format (efs-access, padded)**
Write `$REPO/.terraform-docs.yml`:
```yaml
formatter: "markdown table"
output:
  file: README.md
  mode: inject
sort:
  enabled: true
  by: name
settings:
  anchor: true
  color: true
  default: true
  description: false
  escape: true
  html: true
  indent: 2
  required: true
  sensitive: true
  type: true
```
Then confirm this config reproduces efs-access's CURRENT padded table with ONLY the stale `terraform` row changing — if the padding/columns differ, adjust `settings` until a regen of efs-access changes only the `terraform` version cell (the config must match the tool that last generated efs-access). This calibration is the whole point of Step 2; do not proceed until efs-access regen is content-only.

- [ ] **Step 3: Regenerate all three submodule READMEs against the pinned config**
```bash
cd "$REPO"
for m in launcher dns-record efs-access; do
  "$SCRATCH/terraform-docs" --config "$REPO/.terraform-docs.yml" modules/$m
done
```
(`output.mode: inject` replaces only the content between the `<!-- BEGIN_TF_DOCS -->`/`<!-- END_TF_DOCS -->` markers.)

- [ ] **Step 4: Prove the CONTENT diff is truth-only (whitespace-normalized — NOT a bare string grep)**
```bash
cd "$REPO"
for m in launcher dns-record efs-access; do
  norm() { sed -E 's/[[:space:]]+\|/ |/g; s/\|[[:space:]]+/| /g; s/-{2,}/-/g'; }
  git show HEAD:modules/$m/README.md | norm > /tmp/before_$m
  norm < modules/$m/README.md > /tmp/after_$m
  echo "=== $m content diff (alignment normalized away) ==="
  diff /tmp/before_$m /tmp/after_$m || true
done
# Stale strings must be gone repo-wide (covers status-page/README.md two levels deep — spec S2):
if grep -rn '~> 5\.0\|5\.25\.0\|bendoerr/terraform-null-label' $(find . -name README.md -not -path './.git/*'); then
  echo "STALE ROWS REMAIN"; else echo "v5 + personal-ns purged"; fi
```
Expected: each `diff` shows ONLY real changes — `terraform >= 0.13`/`~> 1.0` → `>= 1.3.0`; launcher/dns-record `aws ~> 5.0` → `~> 6.x` and provider `5.25.0` → a 6.x version; launcher Modules table `label_ecs_svc_update` source flips from `git@github.com:bendoerr/terraform-null-label` → `bendoerr-terraform-modules/...`. NO content lines other than versions/sources. Final line: `v5 + personal-ns purged`. If a `diff` shows non-version content lines, the config (Step 2) is wrong — fix it, don't commit churn.

- [ ] **Step 5: Commit**
```bash
git add .terraform-docs.yml modules/launcher/README.md modules/dns-record/README.md modules/efs-access/README.md
git commit -m "🔧 docs: pin .terraform-docs.yml + regenerate submodule docs (kill stale v5 tables)

Docs are not gated in CI (terraform_docs: false), so launcher/dns-record
still advertised aws ~> 5.0 / provider 5.25.0 while the code pins ~> 6.x, and
launcher's Modules table still pointed at the old personal-namespace null-label
source. The three READMEs had drifted into two different terraform-docs
formats; committing .terraform-docs.yml (v0.20.0) normalizes them to one
reproducible format so future regens are churn-free. Content diff verified
truth-only (whitespace normalized); one-time alignment reformat is intentional."
```

---

### Task 4: Fix the root README TODOs (Usage code block + empty data sections)

**Files:**
- Modify: `README.md` (root) ONLY.

**Reality this task must handle (verified — do NOT trust the "7 TODOs are prose" framing):**
- `## About The Project` (line 29) ALREADY has real prose (the Minecraft/Foundry VTT hook). **DO NOT TOUCH IT.**
- `## Version Constraints` ALREADY has real hand-written prose about the `~> 6.0` *provider* pin (this is the provider constraint, not `required_version` — unrelated to Task 1, leave it).
- The 7 TODOs are: (a) `## Usage` (line ~39) — a broken code block containing literally `TODO\n}`; and (b) six EMPTY terraform-docs data sections — `## Requirements`, `## Providers`, `## Modules`, `## Resources`, `## Inputs`, `## Outputs` (lines ~74–94), each just `TODO`. The repo root has NO `.tf` files (verified), so these six data tables cannot and should not exist at the root of a monorepo.

- [ ] **Step 1: Read the real module behavior** so nothing is invented. Sources of truth (read these): `modules/launcher/examples/complete/` (a working wiring), `modules/launcher` (Lambda that scales an ECS service up on inbound and idles it down after `idle_seconds`), `modules/service` (ECS task/service/cluster), `modules/persistence` + `modules/efs-access` (EFS state), `modules/dns-record` (Route53 + query logging), `modules/notice-discord`/`notice-github`/`notice-parameter-store` (status notices). Concept: on-demand Fargate — spin up on request, idle down to ~zero to save money (the About section already says this).

- [ ] **Step 2: Replace the `## Usage` code block (line ~39) with a real, parse-checked example.** Base it on `modules/launcher/examples/complete/` so it actually reflects usage. Fenced ```hcl block. Do NOT invent inputs — use the example's actual module block + inputs. Sanity-check it parses (`terraform fmt -` on the snippet, or eyeball against the example file). Leave the `## Usage` heading; replace only the body.

- [ ] **Step 3: Replace the six empty data-section TODOs with ONE real `## Modules` index.** Delete the `## Requirements`, `## Providers`, `## Resources`, `## Inputs`, `## Outputs` headings and their `TODO`s (meaningless at a monorepo root with no `.tf`). Keep `## Modules` and fill it with a real submodule table — each of the 8 submodules (`launcher`, `service`, `persistence`, `efs-access`, `dns-record`, `notice-discord`, `notice-github`, `notice-parameter-store`), a one-line description, and a link to `modules/<name>/`. This gives the public Registry landing page real navigation instead of six empty tables. Leave `## Roadmap` and `## Contributing` untouched.

- [ ] **Step 4: Verify no TODO remains and About/Version-Constraints survived**
```bash
cd "$REPO"
grep -c 'TODO' README.md                      # expect 0
grep -q 'Minecraft or Foundry' README.md && echo "About intact" || echo "ERROR: About clobbered"
grep -q '## Version Constraints' README.md && echo "VersionConstraints intact" || echo "ERROR: VC clobbered"
```
Expected: `0`, `About intact`, `VersionConstraints intact`.

- [ ] **Step 5: Commit**
```bash
git add README.md
git commit -m "🔧 docs: fill root README Usage + replace empty data-section TODOs with a module index

The root README shipped literal TODO on the public Registry landing page: a
broken Usage code block, plus six empty terraform-docs data sections
(Requirements/Providers/Modules/Resources/Inputs/Outputs) that can't exist at a
monorepo root with no root .tf. Wrote a real Usage example from
modules/launcher/examples/complete and replaced the six empty sections with a
real ## Modules index of the 8 submodules. About + Version Constraints (already
real prose) left untouched."
```

---

## Self-Review

**Spec coverage:**
- S1 floors → Task 1 ✓  · S2 docs regen → Task 3 ✓ (incl. S4 stale source ref, fixed via regen; repo-wide grep covers status-page/README two levels deep) · S3 README prose → Task 4 ✓ · CI floor-check (added by gates) → Task 2 ✓ · Lilith's existing-workflow razor → Global Constraints (verified clean) ✓.
- Out-of-scope items (CI parity, other repos, missing-README backfill, custodian tests) correctly excluded.

**Placeholder scan:** the only `TODO` strings are the ones being REMOVED (Task 4) — not plan placeholders. Every step has concrete commands + expected output. Absolute paths given (SCRATCH/REPO vars).

**Type/name consistency:** floor values consistent across Task 1 table, Task 2 matrix, and Global Constraints (1.3.0 ×7, 1.9.0 service). `floor-reason:` comment shape identical in constraints + Task 1 Step 3. terraform-docs version (v0.20.0) consistent Task 3 Steps 1/5.

**Plan-review integration (adversarial review, 2026-07-30):** verdict was "Ready after fixes"; all findings resolved —
- B1 (root README section mis-map): Tasks 3/4 re-anchored; Task 3 no longer touches root; Task 4 owns root only (Usage code block + `## Modules` index for the 6 empty data sections); About/Version-Constraints explicitly protected + verified in Task 4 Step 4. No file overlap.
- B2 (terraform-docs format churn guaranteed): `.terraform-docs.yml` pinned; one-time intentional normalization documented; string-grep replaced with a whitespace-normalized CONTENT diff gate (Task 3 Step 4).
- M1 (semi-vacuous grep): folded into the B2 content-diff gate.
- M2 (false `optional()` rationale — repo has ZERO optional()): rationale reframed as org POLICY baseline (hard min is 1.0); commit body corrected.
- M3 (placeholder paths): absolute SCRATCH/REPO vars throughout.
- m2 (S2 misses status-page README): repo-wide `find . -name README.md` grep in Task 3 Step 4.
- m3 (fetch-vs-floor misdiagnosis): Task 1 Step 5 now triages by error text.
- Verified receipts kept: floor table 100% accurate, `service` is the unique 1.9 survivor, action SHAs match test.yml, convention grep traced airtight, null-label/context are public.

## Release note (for step 11 gate, kitten + Lilith)
Raising `required_version` floors is conventionally a **minor** bump (added constraint, no API change; breaks no consumer who could actually run the v6 provider). Confirm against the repo's release mechanism (`release.yml`) at the release gate; do not cut the tag without kitten + Lilith sign-off.
