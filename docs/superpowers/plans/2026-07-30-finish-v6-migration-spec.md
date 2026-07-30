# Renovation Spec — Finish the fargate-on-demand v6 migration

> **Status (2026-07-30):** open questions RESOLVED — floor = org baseline `>= 1.3.0` (floors
> only, never `~>`); `service` keeps `>= 1.9.0` (cross-var validation) as the sole survivor;
> S4 (stale source ref) folds into S2 (the ref lives in stale generated docs, not code — regen
> fixes it); a CI floor-check leg + `convention` self-audit were added by the gates. The
> authoritative, execution-ready artifact is the PLAN
> (`2026-07-30-finish-v6-migration.md`); this spec is retained for S1–S4 traceability.

**Patrol:** 2026-07-30 (Thursday) · **Repo:** `bendoerr-terraform-modules/terraform-aws-fargate-on-demand`
**Author:** Old Man Bendo · **Reviewer/gate:** code-kitten (plan + PR) · **Release gate:** kitten + Lilith

## Problem

The AWS provider was bumped v5 → v6 across this repo (every `versions.tf` now pins
`aws ~> 6.x`), but the migration was never *finished*. Three artifacts still describe the
pre-v6 world, and one is an outright correctness bug:

1. **`required_version` floors lie.** Verified across the 8 submodules + their examples:
   - `>= 0.13` (Terraform, Aug 2020) in: `notice-github`, `notice-parameter-store`,
     `efs-access`, `persistence`, `notice-discord` (+ all `examples/.../versions.tf`).
     **This is impossible**: AWS provider v6 requires Terraform ≥ 1.0, so a user on 0.13
     cannot `terraform init`. The module advertises support it cannot provide.
   - `~> 1.0` (pessimistic `>= 1.0, < 2.0`) in: `launcher`, `dns-record`. Non-standard for
     `required_version` (the `< 2.0` cap is meaningless here) and inconsistent with peers.
   - `>= 1.9` in: `service`. Highest floor in the repo — needs verification whether it
     genuinely uses 1.9 features or is just drift-up.
1. **terraform-docs tables are stale.** e.g. `modules/launcher/README.md` Requirements says
   `aws ~> 5.0` and Providers says `aws 5.25.0` while the code pins `~> 6.32`. These render
   on the **public Terraform Registry** pages. `terraform_docs` is deliberately OFF in CI
   (`lint.yml:30`), so nothing ever caught the drift.
1. **Root README ships literal `TODO`.** 7 of them (`README.md:39` About The Project;
   `:74,:78,:82,:86,:90,:94` Usage/features). Public Registry landing page reads "TODO."
1. **Stale module `source` refs (investigate).** `modules/launcher` sources
   `label_ecs_svc_update` from `git@github.com:bendoerr/terraform-null-label` (the *personal*
   namespace) while sibling refs use `bendoerr-terraform-modules/terraform-null-label` (org).
   Likely a leftover from the org migration; confirm and fix if stale.

## Goal

Make `terraform-aws-fargate-on-demand` tell the truth about what it requires and what it
does — floors, generated docs, README prose, and module sources all consistent with the
v6-era reality. One repo, one PR, real gates.

## Scope

**In:**

- (S1) Reconcile all `required_version` floors (8 submodules + examples) to one truthful org
  standard. Kill `>= 0.13` and `~> 1.0`. \[FLOOR VALUE = open question F1.\] Preserve any
  module that provably needs a higher floor.
- (S2) Regenerate every submodule README's terraform-docs section against current code
  (Requirements/Providers/Resources/Inputs/Outputs). Verify no other stale rows.
- (S3) Replace the 7 root-README TODOs with real About The Project + Usage prose (factual
  technical docs voice — these are module docs, not next.bendoerr.me personal-voice pages).
- (S4) Investigate + fix stale personal-namespace module `source` refs (F-investigate).

**Out (→ backlog for future patrols):**

- CI parity (add codeql / pr-label / scorecard to match template) — Hard Rule #4 tension +
  the CodeQL split is a policy question, not this repo's bug.
- Org-wide floor sweep in the OTHER repos (tfuser, null-context, etc.) — sweep-shaped, not
  renovation-shaped; separate effort.
- Stale `# Use a v5.x.x version` comments in other repos (none in THIS repo).
- TODO README prose in other published modules — fargate sets the pattern first.
- fargate-on-demand-custodian Go tests.

## Approach (high level; detailed steps in the plan)

1. Decide floor (F1) → set every `versions.tf` (module + example) accordingly; `terraform fmt`.
1. Install terraform-docs (not on box); find injection markers (`BEGIN_TF_DOCS`/`END_TF_DOCS`)
   or existing format; regenerate each README section; diff to confirm only truth changed.
1. Write About/Usage prose from the actual module behavior (on-demand Fargate launcher +
   notice/persistence/dns submodules).
1. Resolve S4 module-source refs.
1. Local verify: `terraform fmt -check` + `terraform validate` per module + docs-consistency.
   CI terratest (real AWS) is the authoritative functional gate.

## Open questions (→ family: kitten + Lilith)

- **F1 (real fork): the org Terraform floor standard.** Provider v6 hard-requires ≥ 1.0.
  Options: `>= 1.0` (conservative truthful minimum) vs **`>= 1.3.0` (rec — modern baseline,
  `optional()` object-attr defaults used by the context/label pattern, ecosystem norm)** vs
  per-module true-minimum. Also: keep `service`'s `>= 1.9` if it genuinely uses 1.9 features,
  else normalize to baseline. Sets an org precedent even applied to one repo.
- **F2 (scope sanity):** is fargate-on-demand the right pick, and is the in/out scope right
  (esp. excluding CI parity under Hard Rule #4)? Rec: yes, keep CI out.

## Acceptance / gates

- All `required_version` floors truthful + consistent; no `>= 0.13`, no `~> 1.0`.
- Every README terraform-docs section matches code (no v5 rows anywhere).
- Zero `TODO` in root README; About + Usage read as real docs.
- Module sources consistent (no stray personal-ns refs, unless proven intentional).
- `terraform fmt -check` + `terraform validate` clean per module; CI green (terratest + lint).
- Release/tag: floor-raise SemVer implication decided at the release gate (likely minor —
  added constraint, no API change, breaks no consumer who could actually run v6).

## Risks

- Raising a floor is technically a breaking-ish bump; mitigated because sub-1.3 users can't
  run the v6 provider anyway. Flag at release gate.
- terraform-docs default format vs the repo's existing table style — must match exactly or the
  diff balloons; pin the terraform-docs version/format, diff carefully.
- `service` `>= 1.9`: don't lower a genuinely-needed floor. Verify before touching.
