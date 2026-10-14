"""
Stage-1 Auto-Rig pairwise ranker (distill simulator overall scores).

Usage:
  python ml/autorug_rank/train_ranker.py --data ml/autorug_rank/smoke
  python ml/autorug_rank/train_ranker.py --data ml/datasets/autorug_rank --out ml/runs/autorug_rank
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

# Fixed slots so variable furniture inventories become a fixed vector.
_SLOTS = (
    "desk",
    "chair",
    "bed",
    "lamp",
    "fan",
    "ac",
    "shelf",
    "sofa",
    "pc",
    "monitor",
    "table",
    "plant",
    "other",
)


def _slot_for(item: dict) -> str:
    key = (item.get("iconName") or item.get("id") or "other").lower()
    for s in _SLOTS:
        if s == "other":
            continue
        if s in key:
            return s
    return "other"


def layout_features(row: dict) -> np.ndarray:
    cols = max(1.0, float(row["grid_cols"]))
    rows = max(1.0, float(row["grid_rows"]))
    w = row["weights"]
    by_slot: dict[str, list[dict]] = {s: [] for s in _SLOTS}
    for item in row["layout"]["items"]:
        by_slot[_slot_for(item)].append(item)

    feats: list[float] = [
        float(w["airflow"]),
        float(w["lighting"]),
        float(w["ergonomics"]),
        float(w["spatial"]),
        cols / 12.0,
        rows / 12.0,
        1.0 if row["labels"].get("collision_ok", True) else 0.0,
    ]
    for s in _SLOTS:
        items = by_slot[s]
        if not items:
            feats.extend([0.0, 0.0, 0.0, 0.0, 0.0])
            continue
        x = float(np.mean([float(i["gridX"]) for i in items]) / cols)
        y = float(np.mean([float(i["gridY"]) for i in items]) / rows)
        yaw = float(np.deg2rad(np.mean([float(i["yawDegrees"]) for i in items])))
        feats.extend([1.0, x, y, float(np.sin(yaw)), float(np.cos(yaw))])
    return np.asarray(feats, dtype=np.float64)


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def build_pair_matrix(
    layouts: dict[str, dict], pairs: list[dict], split: str
) -> tuple[np.ndarray, np.ndarray]:
    xs: list[np.ndarray] = []
    ys: list[int] = []
    for p in pairs:
        if p.get("split") != split:
            continue
        a = layouts.get(p["layout_a_id"])
        b = layouts.get(p["layout_b_id"])
        if a is None or b is None:
            continue
        fa = layout_features(a)
        fb = layout_features(b)
        # Positive when A wins; also add swapped row for balance.
        if p["winner_id"] == p["layout_a_id"]:
            xs.append(fa - fb)
            ys.append(1)
            xs.append(fb - fa)
            ys.append(0)
        else:
            xs.append(fa - fb)
            ys.append(0)
            xs.append(fb - fa)
            ys.append(1)
    if not xs:
        return np.zeros((0, 1)), np.zeros((0,), dtype=np.int64)
    return np.stack(xs), np.asarray(ys, dtype=np.int64)


def main() -> None:
    ap = argparse.ArgumentParser(description="Train Auto-Rig pairwise ranker")
    ap.add_argument("--data", type=Path, required=True, help="Dir with layouts.jsonl + pairs.jsonl")
    ap.add_argument(
        "--out",
        type=Path,
        default=Path("ml/runs/autorug_rank"),
        help="Checkpoint directory",
    )
    args = ap.parse_args()

    layouts_rows = load_jsonl(args.data / "layouts.jsonl")
    pairs = load_jsonl(args.data / "pairs.jsonl")
    layouts = {r["layout_id"]: r for r in layouts_rows}

    x_train, y_train = build_pair_matrix(layouts, pairs, "train")
    x_val, y_val = build_pair_matrix(layouts, pairs, "val")

    if len(y_train) < 4:
        raise SystemExit(
            f"Need more train pairs (got {len(y_train)}). Dump a larger dataset."
        )

    model = Pipeline(
        [
            ("scaler", StandardScaler()),
            (
                "clf",
                LogisticRegression(
                    max_iter=2000,
                    class_weight="balanced",
                ),
            ),
        ]
    )
    model.fit(x_train, y_train)

    train_acc = accuracy_score(y_train, model.predict(x_train))
    val_acc = (
        accuracy_score(y_val, model.predict(x_val)) if len(y_val) else float("nan")
    )
    print(f"train pairwise acc: {train_acc:.3f} (n={len(y_train)})")
    print(f"val   pairwise acc: {val_acc:.3f} (n={len(y_val)})")

    # Top-1 agreement: for each room+weights group in val, does argmax model match argmax overall?
    groups: dict[str, list[dict]] = {}
    for row in layouts_rows:
        if row.get("split") != "val":
            continue
        key = f"{row['room_id']}|{row['weights']}"
        groups.setdefault(key, []).append(row)

    hits = 0
    total = 0
    for group in groups.values():
        if len(group) < 2:
            continue
        feats = [layout_features(row) for row in group]
        wins = np.zeros(len(group), dtype=np.float64)
        for i in range(len(group)):
            for j in range(len(group)):
                if i == j:
                    continue
                # Predict whether i beats j.
                if model.predict([(feats[i] - feats[j])])[0] == 1:
                    wins[i] += 1
        pred_best = group[int(np.argmax(wins))]["layout_id"]
        true_best = max(group, key=lambda r: float(r["labels"]["overall"]))[
            "layout_id"
        ]
        hits += int(pred_best == true_best)
        total += 1
    top1 = hits / total if total else float("nan")
    print(f"val top-1 vs simulator: {top1:.3f} (groups={total})")

    args.out.mkdir(parents=True, exist_ok=True)
    ckpt = args.out / "pairwise_logreg.joblib"
    joblib.dump({"model": model, "slots": _SLOTS}, ckpt)
    meta = {
        "train_pairwise_acc": train_acc,
        "val_pairwise_acc": val_acc,
        "val_top1_vs_simulator": top1,
        "train_pairs": int(len(y_train)),
        "val_pairs": int(len(y_val)),
        "feature_dim": int(x_train.shape[1]),
        "data": str(args.data),
    }
    (args.out / "metrics.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"Wrote {ckpt}")
    print(f"Wrote {args.out / 'metrics.json'}")


if __name__ == "__main__":
    main()
