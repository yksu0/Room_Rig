#!/usr/bin/env python3
"""Build / fetch a TFLite detector for Room Rig Scan.

Windows note: Ultralytics LiteRT/TFLite *export* is Linux/macOS-only in recent
versions. This script therefore:

1. Tries local `format=tflite` / `format=litert` export when possible.
2. Otherwise downloads a public YOLOv8n COCO TFLite (smoke-test weights).
3. Writes COCO-80 labels next to the model.

Outputs (gitignored weights):
  assets/models/yolo_roomrig.tflite
  assets/models/yolo_roomrig_labels.txt
  ml/out/  (copies / intermediates)
"""

from __future__ import annotations

import json
import shutil
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ML_DIR = Path(__file__).resolve().parent
OUT_DIR = ML_DIR / "out"
ASSETS = REPO / "assets" / "models"
TARGET_TFLITE = ASSETS / "yolo_roomrig.tflite"
TARGET_LABELS = ASSETS / "yolo_roomrig_labels.txt"

# Public Android sample that ships a YOLOv8 COCO TFLite (~3.3 MB).
GITHUB_TFLITE_API = (
    "https://api.github.com/repos/surendramaran/YOLOv8-TfLite-Object-Detector/"
    "contents/app/src/main/assets/model.tflite"
)

COCO80 = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
    "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
    "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
    "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
    "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear",
    "hair drier", "toothbrush",
]


def _write_labels() -> None:
    TARGET_LABELS.write_text("\n".join(COCO80) + "\n", encoding="utf-8")
    # Aspirational Room Rig class list for a future custom head (not used by smoke weights).
    roomrig = [
        "door", "window", "desk", "chair", "bed", "sofa", "tv", "monitor",
        "pc", "lamp", "fan", "ac", "shelf", "wardrobe", "plant", "purifier",
        "heater", "blinds", "mat", "cable_tray", "light_bar", "monitor_arm",
    ]
    target = ASSETS / "yolo_roomrig_target_labels.txt"
    target.write_text("\n".join(roomrig) + "\n", encoding="utf-8")
    (OUT_DIR / "yolo_roomrig_target_labels.txt").write_text(
        "\n".join(roomrig) + "\n", encoding="utf-8"
    )
    print(f"  also wrote aspirational Room Rig labels → {target.name}")


def _find_tflite(root: Path) -> Path | None:
    candidates = sorted(root.rglob("*.tflite"), key=lambda p: p.stat().st_size, reverse=True)
    for p in candidates:
        name = p.name.lower()
        if "float32" in name or "float16" in name:
            return p
    for p in candidates:
        name = p.name.lower()
        if "int8" not in name and "integer" not in name:
            return p
    return candidates[0] if candidates else None


def _try_ultralytics_export() -> Path | None:
    try:
        from ultralytics import YOLO
    except ImportError:
        print("ultralytics not installed — skip local export")
        return None

    print("Loading YOLOv8n…")
    model = YOLO("yolov8n.pt")
    for fmt in ("tflite", "litert"):
        try:
            print(f"Trying Ultralytics export format={fmt!r}…")
            export_path = Path(model.export(format=fmt, imgsz=640))
            search = export_path if export_path.is_dir() else export_path.parent
            hit = _find_tflite(search) or _find_tflite(Path.cwd())
            if hit is not None:
                return hit
        except Exception as e:
            print(f"  export {fmt} failed: {e}")
    return None


def _download_public_tflite() -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Downloading public YOLOv8 TFLite via GitHub API…")
    req = urllib.request.Request(
        GITHUB_TFLITE_API,
        headers={
            "Accept": "application/vnd.github.raw+json",
            "User-Agent": "room-rig-ml-export",
        },
    )
    data = urllib.request.urlopen(req, timeout=120).read()
    if len(data) < 100_000:
        # Might be JSON metadata instead of raw bytes.
        meta = json.loads(data.decode("utf-8"))
        dl = meta.get("download_url")
        if not dl:
            raise RuntimeError(f"Unexpected GitHub API payload: {meta.keys()}")
        data = urllib.request.urlopen(dl, timeout=120).read()
    out = OUT_DIR / "model_public_yolov8.tflite"
    out.write_bytes(data)
    print(f"  downloaded {len(data)} bytes → {out}")
    return out


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)

    tflite = _try_ultralytics_export()
    if tflite is None:
        print("Local TFLite export unavailable on this OS — using public smoke-test weights.")
        tflite = _download_public_tflite()

    shutil.copy2(tflite, OUT_DIR / tflite.name)
    shutil.copy2(tflite, TARGET_TFLITE)
    _write_labels()

    size_mb = TARGET_TFLITE.stat().st_size / (1024 * 1024)
    print(f"Wrote {TARGET_TFLITE} ({size_mb:.1f} MB)")
    print(f"Wrote {TARGET_LABELS} ({len(COCO80)} COCO classes)")
    print("Rebuild/install the Flutter app so Scan can load the YOLO detector.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
