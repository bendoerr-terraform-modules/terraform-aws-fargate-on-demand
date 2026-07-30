# Finish the fargate-on-demand v6 migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `terraform-aws-fargate-on-demand` tell the truth about what Terraform it requires and what it does — floors, generated docs, README prose, and a CI receipt that keeps them honest.

**Architecture:** The AWS provider was bumped v5→v6 (`aws ~> 6.x` everywhere) but the migration was never finished: `required_version` floors, terraform-docs tables, and the README lag behind. Fix the floors to one truthful org standard, add a CI leg that makes each floor executable truth, regenerate the stale docs, and write the README prose that ships as literal `TODO` on the public Registry.

**Tech Stack:** Terraform (HCL), terraform-docs, GitHub Actions, terratest (existing, untouched).

**Repo:** `bendoerr-terraform-modules/terraform-aws-fargate-on-demand`
**Branch:** `renovation/finish-v6-migration`
**Reviewer/gate:** code-kitten (plan + PR). Release/tag gate: kitten + Lilith.
**Spec:** committed beside this file at `docs/superpowers/plans/2026-07-30-finish-v6-migration-spec.md` (S1–S4 trace there). Both spec + plan are TEMPORARY review artifacts — `git rm` both at step 10 before merge so the shipped module stays clean.
**Provenance:** adversarial cold-subagent review + independent execution-verified reviews by code-kitten and Lilith (Discord family room, 2026-07-30). Both ran the sketchy parts on a fresh clone; findings folded in (arch, canon markdown chain, scoped git-config).

## Global Constraints

- **Working paths (absolute, no guessing):** scratchpad = `/tmp/claude-1001/-home-ombb-omyac/9ea1bd85-ed21-4a2d-9cf8-0347e52637b1/scratchpad`; repo clone = `$SCRATCH/fargate-reno`. Every step below assumes `SCRATCH=/tmp/claude-1001/-home-ombb-omyac/9ea1bd85-ed21-4a2d-9cf8-0347e52637b1/scratchpad` and `REPO=$SCRATCH/fargate-reno`.
- **Floor standard (verbatim):** *Modules declare `required_version = ">= 1.3.0"`, floors only, never `~>`.* Upper caps (`~>`, `<`) belong to root modules, never reusable modules.
- **Rationale (accurate for THIS repo):** `>= 1.3.0` is a deliberate ORG-WIDE POLICY baseline (1.3.0 is the floor of the org's pattern language — where the `optional()` context/label idiom lives ACROSS the org). NOTE: this specific repo has ZERO `optional()` usage (verified) and no code feature above TF 1.0 except `service`'s cross-var validation — so this repo's hard code-driven minimum is 1.0 (aws provider v6). We adopt 1.3.0 anyway as the org standard for consistency. Commit bodies must say "adopt org baseline >= 1.3.0 (policy floor; this repo's hard minimum is 1.0)" — do NOT claim this repo uses `optional()`.
- **Survivor deviations** (floor above 1.3.0) are allowed ONLY with a one-line greppable receipt comment on the `required_version` line: `# floor-reason: <feature> requires Terraform <x.y>`. Baseline (1.3.0) modules carry NO comment. Any floor >1.3.0 lacking `floor-reason:` is an audit failure by definition.
- **Confirmed survivor:** `modules/service` = `>= 1.9.0` — `task_memory`'s validation condition references `var.task_cpu` (cross-variable validation, TF 1.9). This is the ONLY survivor; every other module has no cross-var validation and no `optional()`.
- **Platform:** this box is **aarch64 (arm64)** — every downloaded binary MUST be the `linux_arm64` / `linux-arm64` build (verified: terraform 1.3.0/1.9.0 and terraform-docs v0.24.0 all publish arm64). An `amd64` download dies with `Exec format error` at the first command.
- **terraform-docs = the ORG CANON CHAIN, verbatim (do NOT invent a format or a `.terraform-docs.yml`):** terraform-docs **v0.24.0** → `markdown table --indent 3 --output-file README.md --output-mode inject <module>` → `mdformat==0.7.17` on the result. This is the exact chain the org reusable's (currently-off) terraform-docs drift job runs (`--indent 3`), so producing canon now = zero drift the day that gate flips on. The chain runs FLAGS, not a config file — do NOT commit a `.terraform-docs.yml` (an auto-discovered config that disagrees with the flags is a precedence fight). Execution-verified idempotent (kitten ran it: passes 2 & 3 byte-identical) and `escape` is moot (v0.24.0 emits `\_`, mdformat strips it). The `--indent 3` bumps in-marker headings to `###` and re-sorts/realigns tables — this is the SANCTIONED one-time normalization; prose OUTSIDE the markers is left byte-untouched.
- **ALWAYS-ON markdown gate:** the reusable `lint.yml` runs `python3 -m mdformat --check .` (frozen `0.7.17`) on EVERY PR against EVERY markdown file (not just README blocks). Any markdown this plan writes — regenerated READMEs, the root README, AND any committed spec/plan doc — MUST be mdformat-clean or the PR fails. Local equivalent on this box (no pip module; `uv` is present): `uvx --from 'mdformat==0.7.17' mdformat --check .` (same version ⇒ byte-identical to CI's `python3 -m mdformat`).
- **CI scope:** the new floor-check leg is IN (it is the floor change's *receipt*, ruled not a Hard-Rule-#4 violation by both gates). Workflow *parity* (codeql/pr-label/scorecard) is OUT (Ben policy call). The reusable's terraform-docs drift job stays OFF (it targets root `.`, which doesn't fit this multi-module repo — the org already flagged it as a "separate drift-fix"; out of scope, backlog). No existing workflow pins TF below the floor (`setup-terraform` unpinned=latest) — nothing to fix there.
- **Hard rules:** never commit secrets; never `git push --force`; throttle GitHub writes; conventional/gitmoji commit messages per org convention; never mutate global git config (scope with `GIT_CONFIG_GLOBAL`).

## File Structure (what changes)

- `modules/*/versions.tf` (8) + `modules/*/examples/**/versions.tf` + `modules/*/examples/**/ctx.tf` — `required_version` floors. (Task 1)
- `.github/workflows/floor-check.yml` — NEW. Matrix `init -backend=false && validate` pinned to each module's exact floor + a `convention` self-policing grep job. (Task 2)
- `.terraform-docs.yml` — NEW (repo root). Pins terraform-docs format so regens are reproducible. (Task 3)
- `modules/launcher/README.md`, `modules/dns-record/README.md`, `modules/efs-access/README.md` — regenerate marker-wrapped terraform-docs sections against the pinned config. (Task 3)
- `README.md` (root) — Usage code block (real example) + replace six empty terraform-docs data-section TODOs with a real `## Modules` index. About + Version Constraints ALREADY real prose, untouched. (Task 4)
- **Root README and submodule READMEs are owned by different tasks (4 vs 3) with NO file overlap** — root has no terraform-docs markers/`.tf`.

______________________________________________________________________

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

- \[ \] **Step 1: Install pinned Terraform binaries for the local proof**

```bash
SCRATCH=/tmp/claude-1001/-home-ombb-omyac/9ea1bd85-ed21-4a2d-9cf8-0347e52637b1/scratchpad
REPO=$SCRATCH/fargate-reno
cd "$SCRATCH"
# BOX IS aarch64 → linux_arm64 (amd64 = "Exec format error" at the first command)
for v in 1.3.0 1.9.0; do
  curl -sSL -o tf_$v.zip https://releases.hashicorp.com/terraform/$v/terraform_${v}_linux_arm64.zip
  mkdir -p tfbin/$v && (cd tfbin/$v && unzip -oq ../../tf_$v.zip)
done
"$SCRATCH/tfbin/1.3.0/terraform" version   # expect Terraform v1.3.0
```

- \[ \] **Step 2: Configure a SCOPED git rewrite so `terraform init` fetches the SSH module sources over https — WITHOUT mutating global git config**
  `terraform-null-label` and `terraform-null-context` are both PUBLIC (verified) — plain https, no token. Write the rewrite to a scratch git config and export `GIT_CONFIG_GLOBAL` so terraform's git subprocesses inherit it; the box-wide `~/.gitconfig` is never touched:

```bash
git config --file "$SCRATCH/gitconfig-tf" url."https://github.com/".insteadOf "git@github.com:"
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig-tf"   # keep exported through Step 5
```

- \[ \] **Step 3: Edit every floor per the table.** In each `versions.tf`/`ctx.tf`, set `required_version = ">= 1.3.0"` (no `~>`, no cap). For `modules/service/versions.tf` ONLY:

```hcl
required_version = ">= 1.9.0" # floor-reason: cross-variable validation (var.task_memory references var.task_cpu) requires Terraform 1.9
```

- \[ \] **Step 4: Format check** (use the pinned tfbin, not a bare `terraform` of unknown version on PATH)

```bash
cd "$REPO" && "$SCRATCH/tfbin/1.9.0/terraform" fmt -recursive -check
```

Expected: exit 0 (no diff). If it reformats, `"$SCRATCH/tfbin/1.9.0/terraform" fmt -recursive` then re-run `-check`.

- \[ \] **Step 5: Prove every floor is executable truth (local, the same check CI will run in Task 2)**

```bash
cd "$REPO"
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig-tf"   # from Step 2 — terraform's git children inherit it
fails=""
# baseline modules on 1.3.0
for m in dns-record efs-access launcher notice-discord notice-github notice-parameter-store persistence; do
  (cd modules/$m && rm -rf .terraform && "$SCRATCH/tfbin/1.3.0/terraform" init -backend=false -input=false && "$SCRATCH/tfbin/1.3.0/terraform" validate) || fails="$fails $m"
done
# survivor on 1.9.0
(cd modules/service && rm -rf .terraform && "$SCRATCH/tfbin/1.9.0/terraform" init -backend=false -input=false && "$SCRATCH/tfbin/1.9.0/terraform" validate) || fails="$fails service"
if [ -n "$fails" ]; then echo "FLOOR PROOF FAILED:$fails"; else echo "all floors proven"; fi
```

Expected: every module prints `Success! The configuration is valid.` on its pinned floor, and the final line is `all floors proven`. **If the step prints `FLOOR PROOF FAILED`, the task is NOT done** — triage each named module below; do not proceed to Step 6.
**Triage a FAILED module by reading the actual error** (\[\[feedback-verify-failure-log\]\]):

- error mentions `Unsupported Terraform Core version` / `required_version` → genuine floor lie: the module's true (possibly transitive, via a null-label ref) minimum is higher. Raise that module's floor to the real minimum + add a `# floor-reason:` comment naming the cause. Do NOT paper over it.

- error mentions module download / git / network / `Failed to download` → a FETCH problem, NOT a floor problem. Fix the fetch (Step 2 rewrite) and re-run. Do NOT raise the floor.

- \[ \] **Step 6: Confirm no lies remain**

```bash
grep -rn 'required_version' --include='*.tf' . | grep -E '0\.13|~>' && echo "STILL LYING" || echo "clean"
grep -rn 'required_version = ">= 1.9' --include='*.tf' . | grep -v 'floor-reason' && echo "UNDOCUMENTED HIGH FLOOR" || echo "receipts present"
```

Expected: `clean` and `receipts present`.

- \[ \] **Step 7: Commit**

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

______________________________________________________________________

### Task 2: CI floor-check leg (the receipt / drift-guard)

**Files:**

- Create: `.github/workflows/floor-check.yml`

**Interfaces:**

- Consumes: the floors set in Task 1 (matrix pins to them).
- Produces: a required-ish PR check proving each module inits+validates on its exact declared floor.

**Rationale (record in commit body):** the bug was *drift* — code moved, floor didn't. A comment can't detect re-drift; an executable check can. init pinned to the exact floor also enforces transitive floors (a child-module ref needing >floor fails loudly). Both gates ruled this is the floor change's receipt, not workflow renovation → not a Hard-Rule-#4 violation.

**Why two CI legs (verbatim, for the commit/PR body):** *terratest on unpinned-latest above, pin-to-floor validate below — the supported range bracketed at both ends, floor proven, ceiling tracked.*

- \[ \] **Step 1: Write the workflow**

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
            api.github.com:443
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

- \[ \] **Step 2: Lint the workflow** (if/else — do NOT `actionlint || python`, which swallows a real actionlint failure)

```bash
cd "$REPO"
if command -v actionlint >/dev/null 2>&1; then
  actionlint .github/workflows/floor-check.yml
else
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/floor-check.yml'))" && echo "yaml parse ok (actionlint unavailable)"
fi
```

Expected: no errors (actionlint clean, or a clean yaml parse if actionlint isn't installed).

- \[ \] **Step 3: Commit**

```bash
git add .github/workflows/floor-check.yml
git commit -m "🔧 ci: add floor-check — init+validate each module at its exact required_version

Makes the version floor executable truth instead of a comment: the bug we
just fixed was drift (code moved, floor didn't), and only a check pinned to
the exact floor catches re-drift + transitive floor lies. Additive receipt
for the floor change; no cloud creds (validate needs none)."
```

Note: the `floor` matrix covers the 8 MODULES only — the `examples/**` floors set in Task 1 get shape-policed by the `convention` job but are not init-proven (acceptable: examples are demonstrations, not published modules). Real proof of the matrix runs when the PR opens; if a module fails there, triage exactly as Task 1 Step 5 (distinguish a genuine floor lie from a fetch/network failure — do NOT reflexively raise the floor).

______________________________________________________________________

### Task 3: Regenerate submodule terraform-docs via the ORG CANON CHAIN

**Files:**

- Modify: `modules/launcher/README.md`, `modules/dns-record/README.md`, `modules/efs-access/README.md` (marker-wrapped sections regen; prose outside markers left byte-untouched).
- **NO `.terraform-docs.yml`** — the canon chain runs FLAGS; a committed config that disagrees is a precedence fight the day the org drift job flips on. The chain IS the pin.
- **Root `README.md` is NOT touched here** — no markers, no `.tf`; it belongs entirely to Task 4.

**Interfaces:**

- Consumes: floors from Task 1 (the `terraform` Requirements row must become `>= 1.3.0` for launcher/dns-record/efs-access).

**The canon chain (execution-verified by both gates — do exactly this):** terraform-docs **v0.24.0** (linux_arm64) `markdown table --indent 3 --output-file README.md --output-mode inject <module>` → `mdformat==0.7.17` on the resulting README. Verified idempotent (passes 2 & 3 byte-identical); `escape` is moot (v0.24.0 emits `\_`, mdformat strips it); `--indent 3` bumps in-marker headings to `###` and realigns/sorts tables (SANCTIONED one-time normalization); prose outside the markers is untouched.

- \[ \] **Step 1: Install the canon tools (arm64)**

```bash
cd "$SCRATCH"
curl -fsSL https://github.com/terraform-docs/terraform-docs/releases/download/v0.24.0/terraform-docs-v0.24.0-linux-arm64.tar.gz -o tfdocs.tgz
tar -xzf tfdocs.tgz terraform-docs && chmod +x terraform-docs && ./terraform-docs --version   # expect v0.24.0
# mdformat 0.7.17 — box has no pip module; use uv (present) to run the exact pinned version
alias MDFMT='uvx --from mdformat==0.7.17 mdformat'
uvx --from mdformat==0.7.17 mdformat --version   # expect 0.7.17
```

- \[ \] **Step 2: Regenerate each submodule README with the canon chain (terraform-docs → mdformat)**

```bash
cd "$REPO"
for m in launcher dns-record efs-access; do
  "$SCRATCH/terraform-docs" markdown table --indent 3 --output-file README.md --output-mode inject "modules/$m"
  uvx --from mdformat==0.7.17 mdformat "modules/$m/README.md"
done
```

(`--output-mode inject` replaces only the content between the `<!-- BEGIN_TF_DOCS -->`/`<!-- END_TF_DOCS -->` markers; mdformat then canonicalizes the whole file.)

- \[ \] **Step 3: Prove idempotency (the real anti-churn gate — regen twice, second pass must be a no-op)**

```bash
cd "$REPO"
for m in launcher dns-record efs-access; do
  "$SCRATCH/terraform-docs" markdown table --indent 3 --output-file README.md --output-mode inject "modules/$m"
  uvx --from mdformat==0.7.17 mdformat "modules/$m/README.md"
done
if git diff --quiet -- modules/*/README.md; then echo "IDEMPOTENT ✓ (second pass no-op)"; else echo "NOT IDEMPOTENT — chain unstable, STOP"; git --no-pager diff --stat -- modules/*/README.md; fi
```

Expected: `IDEMPOTENT ✓`. (Kitten verified this on all three; if it fails, the tool versions are wrong.)

- \[ \] **Step 4: Prove truth (stale strings gone repo-wide + new floors present) AND the always-on markdown gate passes**

```bash
cd "$REPO"
# Stale strings must be gone repo-wide (find, not modules/*, so it covers notice-github/status-page/README.md two levels deep — spec S2):
if grep -rn '~> 5\.0\|5\.25\.0\|bendoerr/terraform-null-label' $(find . -name README.md -not -path './.git/*'); then
  echo "STALE ROWS REMAIN"; else echo "v5 + personal-ns purged ✓"; fi
# New floor present in each regenerated Requirements table:
for m in launcher dns-record efs-access; do
  grep -q 'terraform.*>= 1\.3\.0' "modules/$m/README.md" && echo "$m floor row ✓" || echo "$m floor row MISSING"; done
# The ALWAYS-ON PR gate — every markdown file must be mdformat-canonical:
uvx --from mdformat==0.7.17 mdformat --check .
```

Expected: `v5 + personal-ns purged ✓`, three `floor row ✓`, and `mdformat --check .` exits 0.
**Truth-delta list for PR eyeballs** (kitten verified these are the REAL content changes — expected, not churn):

- *dns-record:* gains an output row `query_log_group_name`; aws requirement → `~> 6.9`; terraform → `>= 1.3.0`.

- *efs-access:* terraform `>= 0.13` → `>= 1.3.0`; `ssh_authorized_keys` description picks up the current variables.tf wording; inputs re-sort.

- *launcher:* terraform `~> 1.0` → `>= 1.3.0`; aws `~> 5.0` → `~> 6.32`; provider rows go pinned→constraint (aws `5.25.0` → `~> 6.32`, archive `2.4.0` → `~> 2.0`); `ecs_cluster`/`ecs_service` inputs flip optional → REQUIRED; Modules table `label_ecs_svc_update` source flips personal-ns → org-ns.

- \[ \] **Step 5: Commit**

```bash
git add modules/launcher/README.md modules/dns-record/README.md modules/efs-access/README.md
git commit -m "🔧 docs: regenerate submodule terraform-docs via the org canon chain

Docs are not gated in CI (terraform_docs drift job OFF — it targets root '.'
and doesn't fit this multi-module repo), so launcher/dns-record still advertised
aws ~> 5.0 / provider 5.25.0 while the code pins ~> 6.x, and launcher's Modules
table still pointed at the old personal-namespace null-label source. Regenerated
with the org canon chain (terraform-docs v0.24.0 markdown table --indent 3 ->
mdformat 0.7.17) so output matches what the drift job will produce when it flips
on: zero future drift. The chain is the pin (no committed config to fight the
flags). Idempotency + mdformat --check verified; --indent 3 heading/alignment
reformat is the sanctioned one-time normalization."
```

______________________________________________________________________

### Task 4: Fix the root README TODOs (Usage code block + empty data sections)

**Files:**

- Modify: `README.md` (root) ONLY.

**Reality this task must handle (verified — do NOT trust the "7 TODOs are prose" framing):**

- `## About The Project` (line 29) ALREADY has real prose (the Minecraft/Foundry VTT hook). **DO NOT TOUCH IT.**

- `## Version Constraints` ALREADY has real hand-written prose about the `~> 6.0` *provider* pin (this is the provider constraint, not `required_version` — unrelated to Task 1, leave it).

- The 7 TODOs are: (a) `## Usage` (line ~39) — a broken code block containing literally `TODO\n}`; and (b) six EMPTY terraform-docs data sections — `## Requirements`, `## Providers`, `## Modules`, `## Resources`, `## Inputs`, `## Outputs` (lines ~74–94), each just `TODO`. The repo root has NO `.tf` files (verified), so these six data tables cannot and should not exist at the root of a monorepo.

- \[ \] **Step 1: Read the real module behavior** so nothing is invented. Sources of truth (read these): `modules/launcher/examples/complete/` (a working wiring), `modules/launcher` (Lambda that scales an ECS service up on inbound and idles it down after `idle_seconds`), `modules/service` (ECS task/service/cluster), `modules/persistence` + `modules/efs-access` (EFS state), `modules/dns-record` (Route53 + query logging), `modules/notice-discord`/`notice-github`/`notice-parameter-store` (status notices). Concept: on-demand Fargate — spin up on request, idle down to ~zero to save money (the About section already says this).

- \[ \] **Step 2: Replace the `## Usage` code block (line ~39) with a real, parse-checked example.** Base it on `modules/launcher/examples/complete/` so it actually reflects usage. Fenced \`\`\`hcl block. Do NOT invent inputs — use the example's actual module block + inputs. Sanity-check it parses (eyeball against the example file, or run `"$SCRATCH/tfbin/1.9.0/terraform" fmt -` on the snippet). Leave the `## Usage` heading; replace only the body.

- \[ \] **Step 3: Replace the six empty data-section TODOs with ONE real `## Modules` index.** Delete the `## Requirements`, `## Providers`, `## Resources`, `## Inputs`, `## Outputs` headings and their `TODO`s (meaningless at a monorepo root with no `.tf`). Keep `## Modules` and fill it with a real submodule table — each of the 8 submodules (`launcher`, `service`, `persistence`, `efs-access`, `dns-record`, `notice-discord`, `notice-github`, `notice-parameter-store`), a one-line description, and a link to `modules/<name>/`. This gives the public Registry landing page real navigation instead of six empty tables. Leave `## Roadmap` and `## Contributing` untouched.

- \[ \] **Step 4: Canonicalize with mdformat (the always-on gate applies to the root README too)**

```bash
cd "$REPO"
uvx --from mdformat==0.7.17 mdformat README.md
```

- \[ \] **Step 5: Verify no TODO remains, About/Version-Constraints survived, and the markdown gate passes**

```bash
cd "$REPO"
! grep -q 'TODO' README.md && echo "no TODO ✓" || { echo "ERROR: TODO remains"; grep -n TODO README.md; }
grep -q 'Minecraft or Foundry' README.md && echo "About intact ✓" || echo "ERROR: About clobbered"
grep -q '## Version Constraints' README.md && echo "VersionConstraints intact ✓" || echo "ERROR: VC clobbered"
uvx --from mdformat==0.7.17 mdformat --check .   # always-on PR gate — must exit 0
```

Expected: `no TODO ✓`, `About intact ✓`, `VersionConstraints intact ✓`, and `mdformat --check .` exits 0.
(Note: `grep -c 'TODO'` is NOT used — it exits 1 when the count is 0, which an exit-code-reading executor misreads as failure; `! grep -q` is the correct success-on-absence test.)

- \[ \] **Step 6: Commit**

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

______________________________________________________________________

## Self-Review

**Spec coverage:**

- S1 floors → Task 1 ✓  · S2 docs regen → Task 3 ✓ (incl. S4 stale source ref, fixed via regen; repo-wide grep covers status-page/README two levels deep) · S3 README prose → Task 4 ✓ · CI floor-check (added by gates) → Task 2 ✓ · Lilith's existing-workflow razor → Global Constraints (verified clean) ✓.
- Out-of-scope items (CI parity, other repos, missing-README backfill, custodian tests) correctly excluded.

**Placeholder scan:** the only `TODO` strings are the ones being REMOVED (Task 4) — not plan placeholders. Every step has concrete commands + expected output. Absolute paths given (SCRATCH/REPO vars).

**Type/name consistency:** floor values consistent across Task 1 table, Task 2 matrix, and Global Constraints (1.3.0 ×7, 1.9.0 service). `floor-reason:` comment shape identical in constraints + Task 1 Step 3. terraform-docs version (v0.24.0) + mdformat (0.7.17) consistent across Global Constraints + Task 3. `$SCRATCH/$REPO` and `GIT_CONFIG_GLOBAL` used consistently.

**Review integration — THREE rounds, all resolved:**

- *Adversarial cold-subagent review:* B1 (root README section mis-map → Tasks 3/4 re-anchored, no file overlap, About/VC protected+verified); B2 (format churn → superseded by the canon chain below); M2 (false optional() rationale → reframed as org POLICY baseline, hard min 1.0); M3 (placeholder paths → absolute vars); m2 (S2 status-page → repo-wide find grep); m3 (fetch-vs-floor → Task 1 Step 5 triages by error text).
- *code-kitten (execution-verified on a fresh clone):* **B1-arch** (box is aarch64; all downloads → linux_arm64); **B2-canon** (terraform-docs v0.20.0 was wrong — no padding knob, calibration deadlock; replaced with the org canon chain terraform-docs **v0.24.0** `--indent 3` → mdformat 0.7.17, verified idempotent, escape moot, NO `.terraform-docs.yml`); **MAJOR git-config** (scoped via `GIT_CONFIG_GLOBAL`, no global mutation); convention egress +api.github.com; Task 4 `! grep -q`; the truth-delta list (verbatim in Task 3 Step 4); and the dessert — the plan doc itself failed `mdformat --check .`, now canonicalized before push.
- *Lilith (independent, execution-verified):* the **always-on `mdformat --check .` gate** the plan never named (now run in Tasks 3 & 4); indent **3** = org canon (confirmed from the reusable at its pinned SHA); actionlint `if/else` (no `||` swallow); tfbin paths not bare `terraform`; Task 1 Step 5 self-judges (exits nonzero on any floor failure); commit the spec beside the plan for S1–S4 traceability.
- Verified receipts kept: floor table 100% accurate (both gates), `service` is the unique 1.9 survivor, action SHAs match test.yml, convention grep traced airtight, null-label/context public, canon chain idempotent.

## Release note (for step 11 gate, kitten + Lilith)

Raising `required_version` floors is conventionally a **minor** bump (added constraint, no API change; breaks no *plausible* consumer — TF 1.0–1.2 + provider v6 is technically legal but not a real-world combo). Current tag is `v0.1.0` → target `v0.2.0`. Confirm against the repo's release mechanism (`release.yml`) at the release gate; do not cut the tag without kitten + Lilith sign-off.
