#!/usr/bin/env python3
"""Desktop smoke test: run best.pt on a few images and save boxed previews.

Usage:
  ml\\.venv\\Scripts\\python ml\\smoke_test_detect.py
  ml\\.venv\\Scripts\\python ml\\smoke_test_detect.py --weights ml/out/yolo_roomrig_best.pt
  ml\\.venv\\Scripts\\python ml\\smoke_test_detect.py --source path/to/photo.jpg
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

from roomrig_classes import ROOMRIG_CLASSES

OUT = ML_DIR / "out" / "smoke"
DEFAULT_WEIGHTS = [
    ML_DIR / "runs" / "roomrig" / "weights" / "best.pt",
    ML_DIR / "out" / "yolo_roomrig_best.pt",
    ML_DIR / "out" / "yolo_roomrig_homeobjects_best.pt",
]


def _pick_weights(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit)
        if not p.exists():
            raise FileNotFoundError(p)
        return p
    for p in DEFAULT_WEIGHTS:
        if p.exists():
            return p
    raise FileNotFoundError("No best.pt found — wait for training or pass --weights")


def _default_sources() -> list[Path]:
    roots = [
        ML_DIR / "datasets" / "roomrig_yolo" / "images" / "val",
        ML_DIR / "datasets" / "extra" / "monitor" / "valid" / "images",
        ML_DIR / "datasets" / "extra" / "inside" / "valid" / "images",
    ]
    exts = {".jpg", ".jpeg", ".png", ".webp"}
    picks: list[Path] = []
    for root in roots:
        if not root.is_dir():
            continue
        for p in sorted(root.iterdir()):
            if p.suffix.lower() in exts:
                picks.append(p)
            if len(picks) >= 8:
                return picks
    return picks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", default="")
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--imgsz", type=int, default=640)
    args = parser.parse_args()

    import numpy as np

    if not hasattr(np, "trapz") and hasattr(np, "trapezoid"):
        np.trapz = np.trapezoid  # type: ignore[attr-defined]

    from ultralytics import YOLO

    weights = _pick_weights(args.weights or None)
    sources = [Path(s) for s in args.source] if args.source else _default_sources()
    if not sources:
        print("No source images found", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    model = YOLO(str(weights))
    print(f"weights={weights}")
    print(f"classes({len(ROOMRIG_CLASSES)})={ROOMRIG_CLASSES}")
    print(f"testing {len(sources)} images → {OUT}")

    hits: dict[str, int] = {n: 0 for n in ROOMRIG_CLASSES}
    for src in sources:
        results = model.predict(
            source=str(src),
            conf=args.conf,
            imgsz=args.imgsz,
            verbose=False,
        )
        r0 = results[0]
        names = r0.names or {}
        labels = []
        if r0.boxes is not None and len(r0.boxes):
            for cls_i in r0.boxes.cls.tolist():
                name = names.get(int(cls_i), str(int(cls_i)))
                labels.append(name)
                if name in hits:
                    hits[name] += 1
        out_img = OUT / f"smoke_{src.stem}.jpg"
        r0.save(filename=str(out_img))
        print(f"  {src.name}: {labels or '(none)'} → {out_img.name}")

    print("\nClass hit counts on this batch:")
    for name, c in hits.items():
        if c:
            print(f"  {name:12} {c}")
    print(f"\nOpen folder: {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
