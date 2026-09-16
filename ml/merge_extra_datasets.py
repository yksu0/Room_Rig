#!/usr/bin/env python3
"""Merge Roboflow extras under ml/datasets/extra/ into roomrig_yolo (append).

Does not wipe HomeObjects remaps already in roomrig_yolo.
Only keeps boxes that map to Room Rig classes; skips images with no kept boxes.
"""

from __future__ import annotations

import random
import shutil
import sys
from pathlib import Path

import yaml

ML_DIR = Path(__file__).resolve().parent
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

from roomrig_classes import CLASS_TO_ID, EXTRA_DATASET_MAPS, ROOMRIG_CLASSES

OUT = ML_DIR / "datasets" / "roomrig_yolo"
EXTRA = ML_DIR / "datasets" / "extra"
IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

# Cap huge single-class dumps so they don't drown HomeObjects.
MAX_TRAIN_PER_SOURCE = {
    "monitor": 1800,
    "shelf": 400,
    "blinds": 800,
    "blinds2": 400,
    "purifier": 300,
    "inside": 500,
    "fan": 800,
    "ac": 600,
    "renovia": 200,
    "vent": 500,
}
MAX_VAL_PER_SOURCE = {
    "monitor": 300,
    "shelf": 80,
    "blinds": 150,
    "blinds2": 80,
    "purifier": 50,
    "inside": 80,
    "fan": 120,
    "ac": 100,
    "renovia": 40,
    "vent": 80,
}


def _load_names(data_yaml: Path) -> list[str]:
    raw = yaml.safe_load(data_yaml.read_text(encoding="utf-8"))
    names = raw.get("names")
    if isinstance(names, dict):
        return [names[i] for i in sorted(names, key=lambda k: int(k))]
    if isinstance(names, list):
        return list(names)
    raise ValueError(f"No names in {data_yaml}")


def _find_split_dirs(root: Path, split: str) -> tuple[Path, Path] | None:
    # Roboflow: train/images + train/labels  (valid → val)
    candidates = [split]
    if split == "val":
        candidates = ["val", "valid", "validation"]
    for name in candidates:
        img = root / name / "images"
        lbl = root / name / "labels"
        if img.is_dir() and lbl.is_dir():
            return img, lbl
        # Alternate: images/train + labels/train
        img2 = root / "images" / name
        lbl2 = root / "labels" / name
        if img2.is_dir() and lbl2.is_dir():
            return img2, lbl2
    return None


def _remap_lines(src_lbl: Path, name_map: dict[str, str], names: list[str]) -> list[str]:
    if not src_lbl.exists():
        return []
    out: list[str] = []
    for line in src_lbl.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split()
        if len(parts) < 5:
            continue
        old_id = int(float(parts[0]))
        if old_id < 0 or old_id >= len(names):
            continue
        src_name = names[old_id]
        mapped = name_map.get(src_name)
        if mapped is None:
            # case-insensitive fallback
            mapped = name_map.get(src_name.lower())
            if mapped is None:
                for k, v in name_map.items():
                    if k.lower() == src_name.lower():
                        mapped = v
                        break
        if mapped is None:
            continue
        out.append(" ".join([str(CLASS_TO_ID[mapped]), *parts[1:]]))
    return out


def _merge_source(source: str, name_map: dict[str, str]) -> dict[str, int]:
    root = EXTRA / source
    data_yaml = root / "data.yaml"
    if not data_yaml.exists():
        print(f"  SKIP {source}: no data.yaml")
        return {}

    names = _load_names(data_yaml)
    stats = {"train_img": 0, "val_img": 0, "train_box": 0, "val_box": 0}

    for split, out_split in (("train", "train"), ("val", "val"), ("test", "train")):
        dirs = _find_split_dirs(root, split if split != "val" else "val")
        if dirs is None and split == "val":
            dirs = _find_split_dirs(root, "valid")
        if dirs is None:
            continue
        img_dir, lbl_dir = dirs
        out_img = OUT / "images" / out_split
        out_lbl = OUT / "labels" / out_split
        out_img.mkdir(parents=True, exist_ok=True)
        out_lbl.mkdir(parents=True, exist_ok=True)

        images = sorted(
            p for p in img_dir.iterdir() if p.suffix.lower() in IMG_EXTS
        )
        random.shuffle(images)
        cap = (
            MAX_TRAIN_PER_SOURCE.get(source)
            if out_split == "train"
            else MAX_VAL_PER_SOURCE.get(source)
        )
        kept_imgs = 0
        for img in images:
            if cap is not None and kept_imgs >= cap and out_split == "train":
                break
            if out_split == "val" and cap is not None and kept_imgs >= cap:
                break
            lines = _remap_lines(lbl_dir / f"{img.stem}.txt", name_map, names)
            if not lines:
                continue
            stem = f"{source}__{img.stem}"
            # Avoid overwriting if re-run
            dst_img = out_img / f"{stem}{img.suffix.lower()}"
            dst_lbl = out_lbl / f"{stem}.txt"
            if dst_img.exists():
                continue
            shutil.copy2(img, dst_img)
            dst_lbl.write_text("\n".join(lines) + "\n", encoding="utf-8")
            kept_imgs += 1
            if out_split == "train":
                stats["train_img"] += 1
                stats["train_box"] += len(lines)
            else:
                stats["val_img"] += 1
                stats["val_box"] += len(lines)

    return stats


def _write_coverage() -> None:
    counts = {n: 0 for n in ROOMRIG_CLASSES}
    n_img = 0
    for lbl in (OUT / "labels" / "train").glob("*.txt"):
        n_img += 1
        for line in lbl.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if not parts:
                continue
            cid = int(float(parts[0]))
            if 0 <= cid < len(ROOMRIG_CLASSES):
                counts[ROOMRIG_CLASSES[cid]] += 1

    report = OUT / "coverage.txt"
    lines = [
        "Room Rig class coverage after HomeObjects + extra merge",
        f"train label files: {n_img}",
        "",
    ]
    for name, c in counts.items():
        status = "OK" if c > 0 else "NO DATA"
        lines.append(f"  {name:14} {c:6}  {status}")
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(report.read_text(encoding="utf-8").encode("ascii", "replace").decode("ascii"))


def main() -> int:
    random.seed(7)
    if not (OUT / "images" / "train").is_dir():
        print("Missing roomrig_yolo — run build_roomrig_dataset.py first", file=sys.stderr)
        return 1

    # Refresh yaml in case class list changed.
    names_block = "\n".join(f"  {i}: {n}" for i, n in enumerate(ROOMRIG_CLASSES))
    (OUT / "data.yaml").write_text(
        f"""# Room Rig detector dataset (HomeObjects + Roboflow extras)
path: {OUT.as_posix()}
train: images/train
val: images/val

nc: {len(ROOMRIG_CLASSES)}
names:
{names_block}
""",
        encoding="utf-8",
    )

    print(f"Merging extras from {EXTRA} into {OUT}")
    for source, name_map in EXTRA_DATASET_MAPS.items():
        print(f"\n== {source} ==")
        stats = _merge_source(source, name_map)
        if stats:
            print(
                f"  +{stats.get('train_img', 0)} train / "
                f"+{stats.get('val_img', 0)} val images; "
                f"boxes train={stats.get('train_box', 0)} val={stats.get('val_box', 0)}"
            )

    print("\nCoverage:")
    _write_coverage()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
