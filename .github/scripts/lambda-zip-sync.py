#!/usr/bin/env python3
"""Assert every committed modules/*/*-lambda-function.zip holds exactly its sibling .py.

archive_file rewrites these at plan time, so a stale one is never deployed, but a committed
artifact holding different code is drift nothing else notices (notice-discord's was stale
from 2023-12-02 to 2026-10-15). Compares EXTRACTED content, never zip bytes: zip bytes carry
mtimes. Run from the repo root.
rc 0 = all match · 1 = at least one stale · 2 = nothing measured.
"""
import glob
import os
import sys
import zipfile

zips = sorted(glob.glob("modules/*/*-lambda-function.zip"))
if not zips:
    print("NOT MEASURED - 0 lambda zips under modules/*/ (run from the repo root)")
    sys.exit(2)

stale = 0
for z in zips:
    py = z[:-len(".zip")] + ".py"
    want = os.path.basename(py)
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
