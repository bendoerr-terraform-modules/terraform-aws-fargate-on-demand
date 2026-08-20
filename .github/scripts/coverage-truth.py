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
except (KeyError, TypeError, json.JSONDecodeError):
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
