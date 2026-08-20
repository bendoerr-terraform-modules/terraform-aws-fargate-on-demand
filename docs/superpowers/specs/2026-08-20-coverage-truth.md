# Coverage truth for terraform-aws-fargate-on-demand

**Date:** 2026-08-20 · **Author:** Old Man Bendo the Bot · **Status:** SETTLED — all four
open questions answered in the family brainstorm 2026-08-20 ~08:17–08:20 ET (Discord msgs
1539971664970915970 / 1539972051362775091, Kitten + Lilith); resolutions recorded below and
in the plan.
**Origin:** Renovation Patrol #4. Found during recon: three independent enumerations of this
repo's submodule population disagree, and each disagreement hides real rot.

## Problem — measured, not asserted

The repo has **8 submodules**: `dns-record`, `efs-access`, `launcher`, `notice-discord`,
`notice-github`, `notice-parameter-store`, `persistence`, `service`.

Three surfaces each carry their own hand-written copy of that population, and no two agree
(all measured 2026-08-20T08:15-04:00 on a fresh clone at `3b1759e`):

| Surface | Covers | Missing |
|---|---|---|
| `test.yml` matrix | 5 of 8 | `efs-access`, `notice-parameter-store`, `service` |
| `dependabot.yml` terraform | 4 of 8 | `efs-access`, `notice-github`, `notice-parameter-store`, `service` |
| `dependabot.yml` gomod | 4 of 6 test dirs | `notice-github/test` (which CI **runs**), `notice-parameter-store/test` |

Concrete casualties of the drift:

1. **`notice-parameter-store` has a complete house-pattern terratest
   (`test/examples_complete_test.go`) that CI has never executed** — it is absent from the
   matrix. A test that never runs rots silently; nobody knows today whether it passes.
1. **`service` (653 lines — the ECS cluster/service/task/IAM/SNS core, the thing this module
   IS) has no example, no test, and no dependabot coverage.** It is exercised by nothing:
   `launcher/examples/complete` wires the upstream `terraform-aws-modules/ecs/aws` registry
   module, *not* this repo's `service` submodule (measured, `ecs.tf:14`) — so there is no
   transitive coverage either. Every green Test gate I've trusted on ~30 dependabot merges
   into this repo said nothing about `service`.
1. **`efs-access`** has a runnable cost-safe example (`examples/complete`, enable-flags
   default `false`) and no test.
1. **`notice-github/test`'s `go.mod` gets no dependabot bumps** while its test runs in CI —
   the exact inverse hole: exercised but frozen.

The class is \[\[remediation-unit-vs-census-unit\]\]: three hand-maintained rosters over one
population, each edited at different times, none checked against the substrate. The next
submodule added to `modules/` repeats all of this by default.

## Goals

1. **Every existing test runs in CI.** `modules/notice-parameter-store/test` joins the
   matrix; whatever rot its first real run exposes gets fixed in this patrol.
1. **Every submodule is dependabot-covered.** terraform ecosystem for all 8 module dirs;
   gomod for every `modules/*/test` dir that exists (including the new ones below).
1. **`efs-access` gets a house-pattern terratest** exercising its existing example.
1. **`service` gets an example + terratest** (scope question Q1 below — bias: include; it is
   the heart of the module and the largest uncovered surface).
1. **A drift tripwire in CI**: a check that fails when the matrix, the dependabot dirs, and
   the on-disk population diverge — so this class of rot cannot re-accumulate silently.
   Three-verdict discipline: mismatch is a FAIL with the diff printed; unreadable inputs are
   NOT MEASURED (rc=2), never a silent pass.

## Non-goals

- No feature work or refactoring inside submodule Terraform beyond what tests force out.
- No changes to other repos (the `terraform-null-context` bare-SHA pin found during recon is
  queued separately, not this patrol).
- No re-litigating the serialized `max-parallel: 1` sandbox arrangement or the nightly-nuke
  schedule (Ben's call, standing).

## Design sketch

- **Matrix**: add `modules/notice-parameter-store/test`, `modules/efs-access/test`,
  `modules/service/test`. Keep `max-parallel: 1` (sandbox account collisions are the known
  constraint, `c568e33`). Watch total wall-clock; 8 serialized terratest applies is the cost
  of truth here.
- **dependabot.yml**: add terraform entries for `efs-access`, `notice-github`,
  `notice-parameter-store`, `service`; gomod entries for `notice-github/test`,
  `notice-parameter-store/test`, `efs-access/test`, `service/test`. Same 14-day cooldown +
  grouping as the org shape.
- **efs-access test**: terratest over `examples/complete` with defaults (`enabled=false`,
  `create_transfer_bucket=false`) — applies IAM role/profile + data lookups only, ~$0 —
  asserting output shape; then one targeted assertion pass with `efs_access_enabled=true`
  to exercise the real instance path (Q2: depth vs cost/flake budget).
- **service example**: `examples/complete` wiring VPC + the submodule with the smallest
  Fargate shape that is still honest (Q3: cost-safe form — e.g. minimal task size, and
  whether a scale-to-zero assert can stand in for a running-service assert).
- **Tripwire**: small script (housed in-repo, run as a `lint.yml` step) that derives the
  population from `modules/*/` on disk and diffs it against (a) the test matrix entries and
  (b) dependabot's directory list. Fails loud with the set difference; refuses (distinct rc)
  if any of the three inputs can't be read. The egress-blocked harden-runner arrangement is
  untouched — the check is pure-local.
- **Allowed-endpoints check**: new tests may need new egress entries (EFS/EC2 endpoints are
  already present; verify for SSM + S3 transfer-bucket paths).

## Risks / knowns

- NPS test first-run rot: its go.mod has never been CI-exercised; expect version drift or a
  broken assertion. Budgeted as fix-forward work, not a surprise.
- Terratest applies real sandbox infra; `service` example must not leave anything running
  (defer-destroy is house pattern; nightly nuke is the backstop, not the plan).
- CI wall-clock growth: 5→8 serialized projects. Acceptable; if it crosses ~60min we discuss
  splitting the matrix concurrency group (not in this patrol).

## Open questions — ANSWERED (family brainstorm 2026-08-20, Kitten + Lilith)

- **Q1 — `service` scope**: **IN, but its own PR** (Kitten) — the cheap truth (matrix +
  dependabot + tripwire + NPS fix) must not be hostage to the hardest new test stabilizing.
- **Q2 — efs-access depth**: **defaults-only this patrol**; `enabled=true` becomes a named
  follow-up issue with a milestone date AND a standing patrol-recon step that re-reads open
  follow-up issues — "a follow-up only exists if something re-reads it" (both peers; the
  un-dated alternative is exactly the notice-parameter-store disease).
- **Q3 — service example cost shape**: **desired-count-0 is the honest shape** — scale-to-
  zero idle is this module's native state; running a task means ECR/NAT egress inside a
  nightly-nuked sandbox, flake for a proof not needed (Kitten). Assert cluster+service
  exist, desired=0, taskdef ACTIVE, IAM assumable, SNS wired.
- **Q4 — tripwire placement**: **lint.yml `paperwork` step** (the `lint` job is a reusable-
  workflow call and cannot take steps).
- **Amendments adopted during the brainstorm**: the tripwire invariant is per-submodule
  ("every modules/\* dir has a test dir AND matrix entry AND dependabot cover"), exemptions
  live in an explicit in-repo allowlist that fails BOTH directions (uncovered-unexempted
  red; stale exemption — dead module or module that grew a test — red), and each arm is
  individually forced red on the pre-fix tree with receipts (Kitten's veto + Lilith's
  refinements; her repo-wide second-road verification: 0 of 64 `.tf` files wire `service`,
  no root module exists — the hole is structural).
