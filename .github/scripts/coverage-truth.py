#!/usr/bin/env python3
"""coverage-truth: the module population, CI test matrix, dependabot config,
golangci workdirs, and the exemption list must all agree.

Verdicts:
  rc=0 PASS
  rc=1 RED           (every failing arm named, set differences listed)
  rc=2 NOT MEASURED  (an input could not be read/parsed, or a population was
                      empty where empty cannot be a clean run)

Exemption file format: one entry per line, `module` or `module:arm` where arm is
one of test-dir|matrix|dependabot|golangci; bare `module` means test-dir.
An exemption suppresses only that arm's demands for that module (note:
`module:dependabot` suppresses BOTH the terraform and gomod demands for it, by
design). Stale entries are RED: dead module, a test-dir exemption on a module
that has grown a test, or any arm exemption whose demanded entry now exists.
"""
import json
import os
import sys

ARM_NAMES = ("test-dir", "matrix", "dependabot", "golangci", "exemptions")


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


def str_list_or_refuse(value, what):
    if not isinstance(value, list) or not value or not all(
        isinstance(e, str) for e in value
    ):
        refuse(f"{what} is not a non-empty list of strings - malformed shape is not a pass")
    return value


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
    terratest_job = test_wf["jobs"]["terratest"]
    matrix = terratest_job["strategy"]["matrix"]["project"]
except (KeyError, TypeError):
    terratest_job, matrix = None, None
if terratest_job is None or not matrix:
    refuse("test.yml: jobs.terratest.strategy.matrix.project missing or empty")
matrix = str_list_or_refuse(matrix, "test.yml matrix.project")

# Membership is not execution. These arms refuse the KNOWN cheap shapes that
# empty per-PR coverage while every roster stays intact: a job-level `if:`, a
# paths-filtered or ABSENT pull_request trigger, and golangci switched off.
# NOT covered (recorded, not closed): branch-narrowing, step-level `if:` on the
# run step, and workflow/job deletion - deletion resistance needs the check
# names in the repo ruleset's required_status_checks, which is an org/Ben call.
if "if" in terratest_job:
    refuse("test.yml: jobs.terratest carries an `if:` gate - roster membership no longer implies execution")
triggers = test_wf.get(True) or test_wf.get("on") or {}
if not (isinstance(triggers, dict) and "pull_request" in triggers):
    refuse("test.yml: no on.pull_request trigger - per-PR coverage is zero with every roster intact")
pr_block = triggers.get("pull_request") or {}
if isinstance(pr_block, dict) and ("paths" in pr_block or "paths-ignore" in pr_block):
    refuse("test.yml: on.pull_request is paths-filtered - roster membership no longer implies execution")

dbot = load_yaml(".github/dependabot.yml")
updates = dbot.get("updates")
if not updates:
    refuse("dependabot.yml: updates missing or empty")


def entry_dirs(u):
    """Both legal spellings: directory: str and directories: [str]."""
    if "directory" in u:
        d = u["directory"]
        if not isinstance(d, str):
            refuse(f"dependabot.yml: non-string directory in {u.get('package-ecosystem')} entry")
        return [d]
    if "directories" in u:
        return str_list_or_refuse(u["directories"], "dependabot.yml directories")
    refuse(f"dependabot.yml: {u.get('package-ecosystem')} entry has neither directory nor directories")


tf_dirs, go_dirs = set(), set()
for u in updates:
    eco = u.get("package-ecosystem")
    if eco == "terraform":
        tf_dirs.update(entry_dirs(u))
    elif eco == "gomod":
        go_dirs.update(entry_dirs(u))
if not tf_dirs or not go_dirs:
    refuse("dependabot.yml: terraform or gomod entry set is empty")

lint_wf = load_yaml(".github/workflows/lint.yml")
try:
    lint_with = lint_wf["jobs"]["lint"]["with"]
    workdirs = json.loads(lint_with["golangci_workdirs"])
except (KeyError, TypeError, json.JSONDecodeError):
    lint_with, workdirs = {}, None
if lint_with.get("golangci") is not True:
    refuse("lint.yml: golangci is not enabled - a full roster with the runner off is not coverage")
if not workdirs:
    refuse("lint.yml: jobs.lint.with.golangci_workdirs missing/unparsable/empty")
workdirs = str_list_or_refuse(workdirs, "lint.yml golangci_workdirs")

expath = os.path.join(ROOT, ".github", "coverage-exemptions.txt")
if not os.path.isfile(expath):
    refuse(".github/coverage-exemptions.txt missing - deleting the allowlist is not a way to pass")
exempt = {}  # module -> set of arms
with open(expath) as f:
    for line in f:
        entry = line.split("#", 1)[0].strip()
        if not entry:
            continue
        module, _, arm = entry.partition(":")
        arm = arm or "test-dir"
        if arm not in ("test-dir", "matrix", "dependabot", "golangci"):
            refuse(f"coverage-exemptions.txt: unknown arm '{arm}' in entry '{entry}'")
        exempt.setdefault(module, set()).add(arm)


def exempted(module, arm):
    return arm in exempt.get(module, set())


# Arms ----------------------------------------------------------------------
want_test_entries = {f"modules/{m}/test" for m in testdirs}
want_tf = {f"/modules/{m}" for m in modules if not exempted(m, "dependabot")}
want_go = {f"/modules/{m}/test" for m in testdirs if not exempted(m, "dependabot")}
have_matrix = set(matrix)
have_wd = set(workdirs)
want_matrix = {f"modules/{m}/test" for m in testdirs if not exempted(m, "matrix")}
want_wd = {f"modules/{m}/test" for m in testdirs if not exempted(m, "golangci")}

stale = []
for m, arms_set in sorted(exempt.items()):
    if m not in modules:
        stale.append(f"exemption '{m}' names a module that does not exist")
        continue
    if "test-dir" in arms_set and m in testdirs:
        stale.append(f"exemption '{m}' is stale: the module has since grown a test dir")
    if "matrix" in arms_set and f"modules/{m}/test" in have_matrix:
        stale.append(f"exemption '{m}:matrix' is stale: the matrix entry exists")
    if "golangci" in arms_set and f"modules/{m}/test" in have_wd:
        stale.append(f"exemption '{m}:golangci' is stale: the workdir entry exists")
    if "dependabot" in arms_set and f"/modules/{m}" in tf_dirs and (
        m not in testdirs or f"/modules/{m}/test" in go_dirs
    ):
        stale.append(f"exemption '{m}:dependabot' is stale: the dependabot entries exist")

arms = {
    "test-dir": [
        f"modules/{m} has no test/ dir and no exemption"
        for m in modules
        if m not in testdirs and not exempted(m, "test-dir")
    ],
    "matrix": (
        [f"{e} has a test dir but is missing from the test.yml matrix"
         for e in sorted(want_matrix - have_matrix)]
        + [f"{e} is in the matrix but has no test dir on disk"
           for e in sorted(have_matrix - want_test_entries)]
    ),
    "dependabot": (
        [f"{d} has no terraform dependabot entry" for d in sorted(want_tf - tf_dirs)]
        + [f"{d} is in dependabot(terraform) but not on disk"
           for d in sorted(tf_dirs - {f'/modules/{m}' for m in modules})]
        + [f"{d} has no gomod dependabot entry" for d in sorted(want_go - go_dirs)]
        + [f"{d} is in dependabot(gomod) but not on disk"
           for d in sorted(go_dirs - {f'/modules/{m}/test' for m in testdirs})]
    ),
    "golangci": (
        [f"{e} has a test dir but is missing from golangci_workdirs"
         for e in sorted(want_wd - have_wd)]
        + [f"{e} is in golangci_workdirs but has no test dir on disk"
           for e in sorted(have_wd - want_test_entries)]
    ),
    "exemptions": stale,
}
if set(arms) != set(ARM_NAMES):
    refuse("arm roster drifted from ARM_NAMES - instrument broken, not a verdict")

# Verdict -------------------------------------------------------------------
red = False
for name, violations in arms.items():
    if violations:
        red = True
        print(f"ARM {name}: RED")
        for item in violations:
            print(f"  - {item}")
    else:
        print(f"ARM {name}: OK")

print(
    f"population: {len(modules)} modules, {len(testdirs)} test dirs, "
    f"{sum(len(v) for v in exempt.values())} exemptions"
)
if red:
    print("COVERAGE TRUTH: RED")
    sys.exit(1)
print("COVERAGE TRUTH: PASS")
sys.exit(0)
