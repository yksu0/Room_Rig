#!/usr/bin/env python3
"""Install Room Rig detector weights into assets/ for Flutter Scan.

Prefers a trained best.pt → TFLite. On Windows, Ultralytics TFLite export often
fails; then we keep ONNX and still install matching 18-class labels so the app
is ready once TFLite is produced (Linux/WSL or later converter).

Usage:
  ml\\.venv\\Scripts\\python ml\\install_roomrig_model.py
  ml\\.venv\\Scripts\\python ml\\install_roomrig_model.py --weights ml/runs/roomrig/weights/best.pt
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

from roomrig_classes import ROOMRIG_CLASSES

REPO = ML_DIR.parent
OUT_DIR = ML_DIR / "out"
ASSETS = REPO / "assets" / "models"
TARGET_TFLITE = ASSETS / "yolo_roomrig.tflite"
TARGET_LABELS = ASSETS / "yolo_roomrig_labels.txt"
TARGET_LABELS_REF = ASSETS / "yolo_roomrig_target_labels.txt"


def _write_labels() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    text = "\n".join(ROOMRIG_CLASSES) + "\n"
    TARGET_LABELS.write_text(text, encoding="utf-8")
    TARGET_LABELS_REF.write_text(text, encoding="utf-8")
    (OUT_DIR / "yolo_roomrig_labels.txt").write_text(text, encoding="utf-8")
    print(f"Wrote {TARGET_LABELS} ({len(ROOMRIG_CLASSES)} Room Rig classes)")


def _find_tflite(root: Path) -> Path | None:
    candidates = sorted(root.rglob("*.tflite"), key=lambda p: p.stat().st_size, reverse=True)
    for p in candidates:
        name = p.name.lower()
        if "float16" in name or "float32" in name:
            return p
    for p in candidates:
        if "int8" not in p.name.lower():
            return p
    return candidates[0] if candidates else None


def _pick_weights(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit)
        if not p.exists():
            raise FileNotFoundError(p)
        return p
    for p in (
        ML_DIR / "runs" / "roomrig" / "weights" / "best.pt",
        OUT_DIR / "yolo_roomrig_best.pt",
        OUT_DIR / "yolo_roomrig_homeobjects_best.pt",
    ):
        if p.exists():
            return p
    raise FileNotFoundError("No best.pt — finish training first")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", default="")
    parser.add_argument("--imgsz", type=int, default=640)
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)

    import numpy as np

    if not hasattr(np, "trapz") and hasattr(np, "trapezoid"):
        np.trapz = np.trapezoid  # type: ignore[attr-defined]

    from ultralytics import YOLO

    weights = _pick_weights(args.weights or None)
    print(f"Exporting from {weights}")
    model = YOLO(str(weights))
    shutil.copy2(weights, OUT_DIR / "yolo_roomrig_best.pt")

    tflite: Path | None = None
    for fmt in ("tflite", "litert"):
        try:
            print(f"Trying format={fmt!r}…")
            export_path = Path(model.export(format=fmt, imgsz=args.imgsz, int8=False))
            search = export_path if export_path.is_dir() else export_path.parent
            tflite = _find_tflite(search) or _find_tflite(weights.parent)
            if tflite is not None:
                break
        except Exception as e:
            print(f"  {fmt} failed: {e}")

    onnx: Path | None = None
    try:
        print("Exporting ONNX fallback…")
        onnx = Path(model.export(format="onnx", imgsz=args.imgsz, simplify=True))
        shutil.copy2(onnx, OUT_DIR / onnx.name)
        print(f"  ONNX → {OUT_DIR / onnx.name}")
    except Exception as e:
        print(f"  ONNX failed: {e}")

    _write_labels()

    if tflite is None:
        print(
            "\nTFLite export unavailable on this OS (common on Windows).\n"
            "Labels are installed. To finish:\n"
            "  1) Copy best.pt to a Linux/WSL machine with ultralytics, OR\n"
            "  2) Convert the ONNX under ml/out/ with onnx2tf / ai-edge-litert\n"
            "  3) Place the .tflite at assets/models/yolo_roomrig.tflite\n"
            "Until then Scan keeps the existing smoke TFLite or heuristics."
        )
        return 3

    shutil.copy2(tflite, OUT_DIR / tflite.name)
    shutil.copy2(tflite, TARGET_TFLITE)
    size_mb = TARGET_TFLITE.stat().st_size / (1024 * 1024)
    print(f"Installed {TARGET_TFLITE} ({size_mb:.1f} MB)")
    print("Rebuild/install the Flutter app so Scan loads the Room Rig detector.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
