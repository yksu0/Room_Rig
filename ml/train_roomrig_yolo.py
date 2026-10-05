#!/usr/bin/env python3
"""Train YOLOv8n on the Room Rig remapped dataset and install TFLite into assets/.

Usage:
  ml\\.venv\\Scripts\\python ml\\build_roomrig_dataset.py
  ml\\.venv\\Scripts\\python ml\\train_roomrig_yolo.py --epochs 40
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
DATA_YAML = ML_DIR / "datasets" / "roomrig_yolo" / "data.yaml"
OUT_DIR = ML_DIR / "out"
ASSETS = REPO / "assets" / "models"
TARGET_TFLITE = ASSETS / "yolo_roomrig.tflite"
TARGET_LABELS = ASSETS / "yolo_roomrig_labels.txt"
RUNS = ML_DIR / "runs" / "detect"


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


def _write_labels() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    text = "\n".join(ROOMRIG_CLASSES) + "\n"
    TARGET_LABELS.write_text(text, encoding="utf-8")
    (ASSETS / "yolo_roomrig_target_labels.txt").write_text(text, encoding="utf-8")
    print(f"Wrote {TARGET_LABELS} ({len(ROOMRIG_CLASSES)} Room Rig classes)")


def _try_export_tflite(best_pt: Path) -> Path | None:
    from ultralytics import YOLO

    model = YOLO(str(best_pt))
    for fmt in ("tflite", "litert"):
        try:
            print(f"Exporting format={fmt!r}…")
            export_path = Path(model.export(format=fmt, imgsz=640, int8=False))
            search = export_path if export_path.is_dir() else export_path.parent
            hit = _find_tflite(search) or _find_tflite(best_pt.parent)
            if hit is not None:
                return hit
        except Exception as e:
            print(f"  export {fmt} failed: {e}")

    # ONNX always works on Windows — keep it for offline conversion.
    try:
        print("Exporting ONNX fallback…")
        onnx = Path(model.export(format="onnx", imgsz=640, simplify=True))
        shutil.copy2(onnx, OUT_DIR / onnx.name)
        print(f"  ONNX at {OUT_DIR / onnx.name}")
    except Exception as e:
        print(f"  ONNX export failed: {e}")
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--model", default="yolov8n.pt")
    parser.add_argument("--device", default="")  # auto
    parser.add_argument("--lr0", type=float, default=None, help="Override initial LR (use ~0.001 for fine-tune)")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    if not DATA_YAML.exists():
        print(f"Missing {DATA_YAML} — run build_roomrig_dataset.py first", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)

    import torch
    from ultralytics import YOLO

    # Ultralytics 8.3.x still calls np.trapz; NumPy 2 renamed it to np.trapezoid.
    import numpy as np

    if not hasattr(np, "trapz") and hasattr(np, "trapezoid"):
        np.trapz = np.trapezoid  # type: ignore[attr-defined]

    device = args.device
    if not device:
        device = "0" if torch.cuda.is_available() else "cpu"
    print(f"Training device={device} torch={torch.__version__} cuda={torch.version.cuda}")

    model = YOLO(args.model)
    train_kw: dict = dict(
        data=str(DATA_YAML),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=device,
        project=str(ML_DIR / "runs"),
        name="roomrig",
        exist_ok=True,
        patience=15,
        workers=2,
        pretrained=True,
        resume=args.resume,
    )
    if args.lr0 is not None:
        train_kw["lr0"] = args.lr0
    results = model.train(**train_kw)

    best = Path(results.save_dir) / "weights" / "best.pt"
    if not best.exists():
        best = RUNS / "roomrig" / "weights" / "best.pt"
    if not best.exists():
        print("best.pt not found after training", file=sys.stderr)
        return 2

    shutil.copy2(best, OUT_DIR / "yolo_roomrig_best.pt")
    print(f"Saved {OUT_DIR / 'yolo_roomrig_best.pt'}")

    tflite = _try_export_tflite(best)
    _write_labels()

    if tflite is None:
        print(
            "TFLite export unavailable on this OS. "
            "Kept best.pt + ONNX under ml/out/. "
            "Falling back to copying public smoke TFLite is NOT done — "
            "labels are Room Rig; run export on Linux or convert ONNX→TFLite."
        )
        # Still try downloading a converter path via onnx2tf if present later.
        return 3

    shutil.copy2(tflite, OUT_DIR / tflite.name)
    shutil.copy2(tflite, TARGET_TFLITE)
    size_mb = TARGET_TFLITE.stat().st_size / (1024 * 1024)
    print(f"Installed {TARGET_TFLITE} ({size_mb:.1f} MB)")
    print("Rebuild/install the Flutter app so Scan loads the Room Rig detector.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
