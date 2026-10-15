#!/usr/bin/env python3
"""Assert every committed modules/*/*-lambda-function.zip holds exactly its sibling .py.

archive_file rewrites these at plan time, so a stale one is never deployed, but a committed
artifact holding different code is drift nothing else notices (notice-discord's was stale
from 2023-12-02 to 2026-10-15). Compares EXTRACTED content, never zip bytes: zip bytes carry
mtimes. Run from the repo root.
rc 0 = all match · 1 = at least one stale · 2 = nothing measured.
"""
import os
import subprocess
import sys
import zipfile

# The population is what git TRACKS, not what the worktree holds: a local plan writes
# untracked zips, and a committed zip deleted from the worktree must still be counted.
# A git pathspec `*` also matches `/`, so this finds lambda zips at ANY depth under
# modules/, not only one directory deep. That is deliberate (the sibling .py lookup is
# per path); do not "fix" it with :(glob) unless you mean to shrink the population.
try:
    listed = subprocess.run(
        ["git", "ls-files", "modules/*/*-lambda-function.zip"],
        check=True, capture_output=True, text=True,
    ).stdout.split()
except (OSError, subprocess.CalledProcessError) as err:
    print(f"NOT MEASURED - git ls-files failed ({err}); run from inside the repo")
    sys.exit(2)

zips = sorted(listed)
if not zips:
    print("NOT MEASURED - 0 tracked lambda zips under modules/*/ (run from the repo root)")
    sys.exit(2)

stale = 0
for z in zips:
    py = z[:-len(".zip")] + ".py"
    want = os.path.basename(py)
    if not os.path.isfile(z):
        print(f"STALE {z}: tracked but missing from the worktree")
        stale += 1
        continue
    if not os.path.isfile(py):
        print(f"STALE {z}: no sibling {py}")
        stale += 1
        continue
    with zipfile.ZipFile(z) as zf:
        names = zf.namelist()
        if names != [want]:
            print(f"STALE {z}: members {names}, want [{want!r}]")
            stale += 1
            continue
        with open(py, "rb") as f:
            if zf.read(want) != f.read():
                print(f"STALE {z}: content differs from {py}")
                stale += 1
                continue
    print(f"OK    {z}")

print(f"-- {len(zips)} zip(s) checked · {stale} stale --")
sys.exit(1 if stale else 0)
