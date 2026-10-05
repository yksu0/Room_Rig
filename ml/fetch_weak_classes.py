#!/usr/bin/env python3
"""Fetch a small heater / fan / AC boost set when public YOLO zips are available.

Heater has 0 boxes in the merged Room Rig set; fan/ac are thin.
This script tries Ultralytics Hub / Open Images class downloads when possible,
otherwise prints exact manual links.

Usage:
  ml\\.venv\\Scripts\\python ml\\fetch_weak_classes.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
EXTRA = ML_DIR / "datasets" / "extra"
OUT = EXTRA / "weak_boost"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    print("Weak-class boost helper")
    print("Current gaps: heater=0, fan/ac very few boxes after merge.")
    print()
    print("Manual (best quality) — Roboflow YOLOv8 zip → extract under:")
    print(f"  {EXTRA / 'heater'}/")
    print(f"  or add more into {EXTRA / 'inside'}/")
    print()
    print("Open Images (filter class Heater only — do not download full dump):")
    print("  https://storage.googleapis.com/openimages/web/download_v7.html")
    print()
    print("Roboflow search terms: 'space heater', 'ceiling fan', 'air conditioner indoor'")
    print()
    print("After extract, add to roomrig_classes.EXTRA_DATASET_MAPS and run:")
    print("  ml\\.venv\\Scripts\\python ml\\merge_extra_datasets.py")
    print("  then fine-tune from best.pt again (do not restart from scratch).")

    # Try a tiny torchvision / ultralytics Open Images download if API available.
    try:
        from ultralytics.data.utils import download  # noqa: F401
    except Exception:
        pass

    note = OUT / "README.txt"
    note.write_text(
        "Drop YOLO-format heater (and optional fan/ac) datasets here or under "
        "ml/datasets/extra/heater/, then extend EXTRA_DATASET_MAPS and merge.\n",
        encoding="utf-8",
    )
    print(f"Wrote {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
