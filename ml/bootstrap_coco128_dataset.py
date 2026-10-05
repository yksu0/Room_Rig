#!/usr/bin/env python3
"""Fast bootstrap: remap Ultralytics coco128 furniture → Room Rig labels and train.

Use while the larger HomeObjects-3K zip is still downloading.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

from roomrig_classes import CLASS_TO_ID, ROOMRIG_CLASSES  # noqa: E402

REPO = ML_DIR.parent
OUT = ML_DIR / "datasets" / "roomrig_yolo"

# COCO-80 index → Room Rig name
COCO_IDX_TO_ROOMRIG: dict[int, str] = {
    56: "chair",
    57: "sofa",
    58: "plant",
    59: "bed",
    60: "desk",  # dining table
    62: "tv",
    63: "pc",  # laptop
    64: "pc",  # mouse → pc cluster cue
    66: "pc",  # keyboard
    73: "shelf",  # book → shelf stand-in
}


def _find_coco128() -> Path | None:
    candidates = [
        Path.home() / "datasets" / "coco128",
        ML_DIR / "datasets" / "coco128",
        REPO / "datasets" / "coco128",
        Path.cwd() / "datasets" / "coco128",
    ]
    for c in candidates:
        if (c / "images" / "train2017").is_dir() or (c / "images" / "train").is_dir():
            return c
    # Ultralytics default cache
    for root in [Path.home() / "AppData" / "Roaming" / "Ultralytics", Path.home()]:
        for p in root.rglob("coco128"):
            if p.is_dir() and ((p / "images").is_dir()):
                return p
    return None


def _ensure_coco128() -> Path:
    found = _find_coco128()
    if found is not None:
        print(f"Using existing coco128 at {found}")
        return found

    print("Downloading coco128 via Ultralytics…")
    from ultralytics.utils.downloads import safe_download
    from ultralytics.utils import DATASETS_DIR

    url = "https://github.com/ultralytics/assets/releases/download/v0.0.0/coco128.zip"
    dest = Path(DATASETS_DIR)
    dest.mkdir(parents=True, exist_ok=True)
    safe_download(url=url, dir=dest, unzip=True)
    found = _find_coco128()
    if found is None:
        # DATASETS_DIR/coco128
        cand = dest / "coco128"
        if cand.is_dir():
            return cand
        raise FileNotFoundError("coco128 download finished but folder not found")
    return found


def _img_and_lbl_dirs(root: Path) -> tuple[Path, Path]:
    for img_rel, lbl_rel in [
        ("images/train2017", "labels/train2017"),
        ("images/train", "labels/train"),
    ]:
        img = root / img_rel
        lbl = root / lbl_rel
        if img.is_dir():
            return img, lbl
    raise FileNotFoundError(f"No images under {root}")


def main() -> int:
    root = _ensure_coco128()
    img_dir, lbl_dir = _img_and_lbl_dirs(root)

    if OUT.exists():
        shutil.rmtree(OUT)
    train_img = OUT / "images" / "train"
    train_lbl = OUT / "labels" / "train"
    val_img = OUT / "images" / "val"
    val_lbl = OUT / "labels" / "val"
    for d in (train_img, train_lbl, val_img, val_lbl):
        d.mkdir(parents=True)

    n_img = 0
    n_box = 0
    files = sorted(
        p
        for p in img_dir.iterdir()
        if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    )
    # 90/10 split
    split_at = max(1, int(len(files) * 0.9))

    for i, img in enumerate(files):
        is_val = i >= split_at
        oimg = val_img if is_val else train_img
        olbl = val_lbl if is_val else train_lbl
        src_lbl = lbl_dir / f"{img.stem}.txt"
        lines_out: list[str] = []
        if src_lbl.exists():
            for line in src_lbl.read_text(encoding="utf-8").splitlines():
                parts = line.split()
                if len(parts) < 5:
                    continue
                cid = int(float(parts[0]))
                mapped = COCO_IDX_TO_ROOMRIG.get(cid)
                if mapped is None:
                    continue
                lines_out.append(" ".join([str(CLASS_TO_ID[mapped]), *parts[1:]]))
                n_box += 1
        shutil.copy2(img, oimg / img.name)
        (olbl / f"{img.stem}.txt").write_text(
            "\n".join(lines_out) + ("\n" if lines_out else ""), encoding="utf-8"
        )
        n_img += 1

    names_block = "\n".join(f"  {i}: {n}" for i, n in enumerate(ROOMRIG_CLASSES))
    (OUT / "data.yaml").write_text(
        f"""# Bootstrap Room Rig dataset from coco128 furniture classes
path: {OUT.as_posix()}
train: images/train
val: images/val
nc: {len(ROOMRIG_CLASSES)}
names:
{names_block}
""",
        encoding="utf-8",
    )

    counts = {n: 0 for n in ROOMRIG_CLASSES}
    for lbl in train_lbl.glob("*.txt"):
        for line in lbl.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if parts:
                counts[ROOMRIG_CLASSES[int(float(parts[0]))]] += 1
    report = ["coco128 bootstrap coverage (train boxes):"]
    for n, c in counts.items():
        report.append(f"  {n:14} {c:5}")
    (OUT / "coverage.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    print(f"Bootstrap dataset: {n_img} images, {n_box} remapped boxes → {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
