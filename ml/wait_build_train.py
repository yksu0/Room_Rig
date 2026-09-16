#!/usr/bin/env python3
"""Wait for HomeObjects zip, build dataset, train Room Rig YOLO, install assets."""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

ML = Path(__file__).resolve().parent
ZIP = ML / "datasets" / "homeobjects-3K.zip"
MIN_BYTES = 350_000_000  # HomeObjects is ~390 MB
PY = ML / ".venv" / "Scripts" / "python.exe"


def main() -> int:
    py = str(PY if PY.exists() else sys.executable)
    print(f"Waiting for {ZIP} (>= {MIN_BYTES} bytes)…")
    while True:
        if ZIP.exists():
            size = ZIP.stat().st_size
            print(f"  zip={size} ({100 * size / 409423784:.1f}% of expected)", flush=True)
            if size >= MIN_BYTES:
                break
        time.sleep(20)

    print("Building remapped dataset…", flush=True)
    r = subprocess.run([py, str(ML / "build_roomrig_dataset.py")], cwd=str(ML.parent))
    if r.returncode != 0:
        return r.returncode

    print("Training…", flush=True)
    r = subprocess.run(
        [
            py,
            str(ML / "train_roomrig_yolo.py"),
            "--epochs",
            "35",
            "--batch",
            "16",
            "--imgsz",
            "640",
        ],
        cwd=str(ML.parent),
    )
    return r.returncode


if __name__ == "__main__":
    raise SystemExit(main())
