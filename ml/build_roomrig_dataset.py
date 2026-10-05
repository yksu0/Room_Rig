#!/usr/bin/env python3
"""Download HomeObjects-3K (+ optional COCO furniture) and rewrite labels to Room Rig ids.

Outputs:
  ml/datasets/roomrig_yolo/{images,labels}/{train,val}/
  ml/datasets/roomrig_yolo/data.yaml
"""

from __future__ import annotations

import random
import shutil
import sys
import zipfile
from pathlib import Path
from urllib.request import urlretrieve

ML_DIR = Path(__file__).resolve().parent
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

from roomrig_classes import (
    CLASS_TO_ID,
    HOMEOBJECTS_TO_ROOMRIG,
    ROOMRIG_CLASSES,
)

REPO = ML_DIR.parent
OUT = ML_DIR / "datasets" / "roomrig_yolo"
HOME_ZIP_URL = (
    "https://github.com/ultralytics/assets/releases/download/v0.0.0/homeobjects-3K.zip"
)
HOME_ROOT = ML_DIR / "datasets" / "homeobjects-3K"

# HomeObjects original class order (from Ultralytics yaml).
HOME_NAMES = [
    "bed",
    "sofa",
    "chair",
    "table",
    "lamp",
    "tv",
    "laptop",
    "wardrobe",
    "window",
    "door",
    "potted plant",
    "photo frame",
]


def _download_homeobjects() -> Path:
    HOME_ROOT.parent.mkdir(parents=True, exist_ok=True)
    marker = HOME_ROOT / "images" / "train"
    if marker.is_dir() and any(marker.iterdir()):
        print(f"HomeObjects already present at {HOME_ROOT}")
        return HOME_ROOT

    zip_path = ML_DIR / "datasets" / "homeobjects-3K.zip"
    if not zip_path.exists():
        print(f"Downloading HomeObjects-3K (~390 MB)…")
        urlretrieve(HOME_ZIP_URL, zip_path)
    print(f"Extracting {zip_path}…")
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(ML_DIR / "datasets")
    # Zip may unpack as homeobjects-3K or nested.
    candidates = [
        ML_DIR / "datasets" / "homeobjects-3K",
        ML_DIR / "datasets" / "homeobjects-3k",
        ML_DIR / "datasets" / "HomeObjects-3K",
    ]
    for c in candidates:
        if (c / "images" / "train").is_dir():
            if c != HOME_ROOT:
                if HOME_ROOT.exists():
                    shutil.rmtree(HOME_ROOT)
                c.rename(HOME_ROOT)
            return HOME_ROOT
    # Search
    for p in (ML_DIR / "datasets").rglob("images"):
        if (p / "train").is_dir():
            root = p.parent
            if root != HOME_ROOT:
                if HOME_ROOT.exists():
                    shutil.rmtree(HOME_ROOT)
                shutil.move(str(root), str(HOME_ROOT))
            return HOME_ROOT
    raise FileNotFoundError("Could not locate HomeObjects images after extract")


def _remap_label_file(src: Path, dst: Path) -> int:
    kept = 0
    lines_out: list[str] = []
    if not src.exists():
        return 0
    for line in src.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split()
        if len(parts) < 5:
            continue
        old_id = int(float(parts[0]))
        if old_id < 0 or old_id >= len(HOME_NAMES):
            continue
        mapped = HOMEOBJECTS_TO_ROOMRIG.get(HOME_NAMES[old_id])
        if mapped is None:
            continue
        new_id = CLASS_TO_ID[mapped]
        lines_out.append(" ".join([str(new_id), *parts[1:]]))
        kept += 1
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("\n".join(lines_out) + ("\n" if lines_out else ""), encoding="utf-8")
    return kept


def _copy_split(split: str) -> tuple[int, int]:
    img_dir = HOME_ROOT / "images" / split
    label_dir = HOME_ROOT / "labels" / split
    out_img = OUT / "images" / split
    out_lbl = OUT / "labels" / split
    out_img.mkdir(parents=True, exist_ok=True)
    out_lbl.mkdir(parents=True, exist_ok=True)

    n_img = 0
    n_box = 0
    for img in sorted(img_dir.glob("*")):
        if img.suffix.lower() not in {".jpg", ".jpeg", ".png", ".bmp", ".webp"}:
            continue
        stem = img.stem
        src_lbl = label_dir / f"{stem}.txt"
        dst_lbl = out_lbl / f"{stem}.txt"
        boxes = _remap_label_file(src_lbl, dst_lbl)
        if boxes == 0 and dst_lbl.exists():
            # Keep empty label files so YOLO still uses the image as background.
            pass
        shutil.copy2(img, out_img / img.name)
        n_img += 1
        n_box += boxes
    return n_img, n_box


def _write_yaml() -> Path:
    yaml_path = OUT / "data.yaml"
    names_block = "\n".join(f"  {i}: {n}" for i, n in enumerate(ROOMRIG_CLASSES))
    yaml_path.write_text(
        f"""# Room Rig detector dataset (remapped public indoor photos)
# Built by ml/build_roomrig_dataset.py from Ultralytics HomeObjects-3K.

path: {OUT.as_posix()}
train: images/train
val: images/val

nc: {len(ROOMRIG_CLASSES)}
names:
{names_block}
""",
        encoding="utf-8",
    )
    return yaml_path


def _write_coverage_report(train_boxes: int, val_boxes: int) -> None:
    # Count per-class instances in train labels.
    counts = {n: 0 for n in ROOMRIG_CLASSES}
    for lbl in (OUT / "labels" / "train").glob("*.txt"):
        for line in lbl.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if not parts:
                continue
            cid = int(float(parts[0]))
            if 0 <= cid < len(ROOMRIG_CLASSES):
                counts[ROOMRIG_CLASSES[cid]] += 1

    report = OUT / "coverage.txt"
    lines = [
        "Room Rig class coverage after HomeObjects remap",
        f"train images → see dataset; train boxes≈{train_boxes}, val boxes≈{val_boxes}",
        "",
    ]
    for name, c in counts.items():
        status = "OK" if c > 0 else "NO DATA (head slot reserved; weak/random until labeled photos added)"
        lines.append(f"  {name:14} {c:6}  {status}")
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # Avoid Windows cp1252 crashes on arrows / unicode in the report.
    print(report.read_text(encoding="utf-8").encode("ascii", "replace").decode("ascii"))


def main() -> int:
    random.seed(7)
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    _download_homeobjects()
    tr_i, tr_b = _copy_split("train")
    va_i, va_b = _copy_split("val")
    yaml_path = _write_yaml()
    _write_coverage_report(tr_b, va_b)

    print(f"Dataset ready: {tr_i} train / {va_i} val images")
    print(f"YAML: {yaml_path}")
    print(
        "Classes with ZERO boxes will not learn — add labeled photos later "
        "(fan, ac, monitor, shelf, upgrades, …)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
