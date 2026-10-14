"""
Stage-1 Auto-Rig ranker (distill simulator overall scores).

Trains:
  - pairwise classifier on feature diffs
  - pointwise regressor on overall score (usually better for top-1)

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
from sklearn.ensemble import (
    HistGradientBoostingClassifier,
    HistGradientBoostingRegressor,
)
from sklearn.linear_model import Ridge
from sklearn.metrics import accuracy_score, mean_absolute_error
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
    "door",
    "window",
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


def _center(item: dict) -> tuple[float, float]:
    return (
        float(item["gridX"]) + float(item["width"]) * 0.5,
        float(item["gridY"]) + float(item["height"]) * 0.5,
    )


def _first(by_slot: dict[str, list[dict]], name: str) -> dict | None:
    items = by_slot.get(name) or []
    return items[0] if items else None


def layout_features(row: dict) -> np.ndarray:
    cols = max(1.0, float(row["grid_cols"]))
    rows = max(1.0, float(row["grid_rows"]))
    diag = float(np.hypot(cols, rows))
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
        float(len(row["layout"]["items"])) / 20.0,
    ]
    centers: dict[str, tuple[float, float]] = {}
    for s in _SLOTS:
        items = by_slot[s]
        if not items:
            feats.extend([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
            continue
        x = float(np.mean([float(i["gridX"]) for i in items]) / cols)
        y = float(np.mean([float(i["gridY"]) for i in items]) / rows)
        yaw = float(np.deg2rad(np.mean([float(i["yawDegrees"]) for i in items])))
        area = float(
            np.mean([float(i["width"]) * float(i["height"]) for i in items])
            / (cols * rows)
        )
        cx, cy = _center(items[0])
        centers[s] = (cx / cols, cy / rows)
        feats.extend([1.0, x, y, float(np.sin(yaw)), float(np.cos(yaw)), area])

    def rel(a: str, b: str) -> list[float]:
        if a not in centers or b not in centers:
            return [0.0, 0.0, 0.0]
        ax, ay = centers[a]
        bx, by = centers[b]
        dx, dy = ax - bx, ay - by
        dist = float(np.hypot(dx * cols, dy * rows) / diag)
        return [dist, dx, dy]

    # Relations that mirror Auto-Rig / comfort heuristics.
    feats.extend(rel("desk", "chair"))
    feats.extend(rel("desk", "window"))
    feats.extend(rel("desk", "door"))
    feats.extend(rel("chair", "door"))
    feats.extend(rel("bed", "door"))
    feats.extend(rel("fan", "ac"))
    feats.extend(rel("lamp", "desk"))
    feats.extend(rel("monitor", "desk"))

    desk = _first(by_slot, "desk")
    chair = _first(by_slot, "chair")
    window = _first(by_slot, "window")
    if desk and chair:
        # Chair should sit roughly in front of desk (yaw ~180 relative).
        d_yaw = float(desk["yawDegrees"])
        c_yaw = float(chair["yawDegrees"])
        delta = ((c_yaw - d_yaw + 180) % 360) - 180
        feats.append(abs(delta) / 180.0)
    else:
        feats.append(0.0)
    if desk and window:
        # Prefer side light: desk yaw not square-on to north window.
        d_yaw = float(desk["yawDegrees"]) % 360.0
        # Window assumed on north (y~0); facing north is yaw 0 in many layouts.
        square_on = min(abs(d_yaw - 0.0), abs(d_yaw - 180.0)) / 180.0
        feats.append(square_on)
    else:
        feats.append(0.0)

    return np.asarray(feats, dtype=np.float64)


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def group_key(row: dict) -> str:
    w = row["weights"]
    return (
        f"{row['room_id']}|"
        f"{w['airflow']:.4f}|{w['lighting']:.4f}|"
        f"{w['ergonomics']:.4f}|{w['spatial']:.4f}"
    )


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


def build_point_matrix(
    layouts_rows: list[dict], split: str
) -> tuple[np.ndarray, np.ndarray]:
    xs: list[np.ndarray] = []
    ys: list[float] = []
    for row in layouts_rows:
        if row.get("split") != split:
            continue
        xs.append(layout_features(row))
        ys.append(float(row["labels"]["overall"]))
    if not xs:
        return np.zeros((0, 1)), np.zeros((0,), dtype=np.float64)
    return np.stack(xs), np.asarray(ys, dtype=np.float64)


def _val_groups(
    layouts_rows: list[dict], *, proposals_only: bool
) -> list[list[dict]]:
    groups: dict[str, list[dict]] = {}
    for row in layouts_rows:
        if row.get("split") != "val":
            continue
        if proposals_only and row.get("labels", {}).get("proposal_tag") == "hard_negative":
            continue
        groups.setdefault(group_key(row), []).append(row)
    return [g for g in groups.values() if len(g) >= 2]


def eval_top1_pairwise(
    model, layouts_rows: list[dict], *, proposals_only: bool = False
) -> tuple[float, int]:
    hits = 0
    total = 0
    for group in _val_groups(layouts_rows, proposals_only=proposals_only):
        feats = [layout_features(row) for row in group]
        wins = np.zeros(len(group), dtype=np.float64)
        for i in range(len(group)):
            for j in range(len(group)):
                if i == j:
                    continue
                proba = model.predict_proba([(feats[i] - feats[j])])[0]
                wins[i] += float(proba[1] if len(proba) > 1 else proba[0])
        pred_best = group[int(np.argmax(wins))]["layout_id"]
        true_best = max(group, key=lambda r: float(r["labels"]["overall"]))[
            "layout_id"
        ]
        hits += int(pred_best == true_best)
        total += 1
    return (hits / total if total else float("nan"), total)


def eval_top1_pointwise(
    model, layouts_rows: list[dict], *, proposals_only: bool = False
) -> tuple[float, int]:
    hits = 0
    total = 0
    for group in _val_groups(layouts_rows, proposals_only=proposals_only):
        preds = model.predict([layout_features(r) for r in group])
        pred_best = group[int(np.argmax(preds))]["layout_id"]
        true_best = max(group, key=lambda r: float(r["labels"]["overall"]))[
            "layout_id"
        ]
        hits += int(pred_best == true_best)
        total += 1
    return (hits / total if total else float("nan"), total)


def eval_ranking_quality(
    score_fn, layouts_rows: list[dict], *, proposals_only: bool = True
) -> dict[str, float]:
    """score_fn(row) -> float; higher is better."""
    top1 = top2 = 0
    regret = []
    total = 0
    for group in _val_groups(layouts_rows, proposals_only=proposals_only):
        scored = [(float(score_fn(r)), r) for r in group]
        scored.sort(key=lambda t: t[0], reverse=True)
        by_true = sorted(
            group, key=lambda r: float(r["labels"]["overall"]), reverse=True
        )
        true_best = by_true[0]
        pred_best = scored[0][1]
        top1 += int(pred_best["layout_id"] == true_best["layout_id"])
        top2_ids = {scored[i][1]["layout_id"] for i in range(min(2, len(scored)))}
        top2 += int(true_best["layout_id"] in top2_ids)
        regret.append(
            float(true_best["labels"]["overall"])
            - float(pred_best["labels"]["overall"])
        )
        total += 1
    if not total:
        return {"top1": float("nan"), "top2": float("nan"), "mean_regret": float("nan"), "n": 0}
    return {
        "top1": top1 / total,
        "top2": top2 / total,
        "mean_regret": float(np.mean(regret)),
        "n": total,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Train Auto-Rig layout ranker")
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
    xp_train, yp_train = build_point_matrix(layouts_rows, "train")
    xp_val, yp_val = build_point_matrix(layouts_rows, "val")

    if len(y_train) < 4:
        raise SystemExit(
            f"Need more train pairs (got {len(y_train)}). Dump a larger dataset."
        )

    pair_model = Pipeline(
        [
            ("scaler", StandardScaler()),
            (
                "clf",
                HistGradientBoostingClassifier(
                    max_depth=6,
                    learning_rate=0.08,
                    max_iter=200,
                ),
            ),
        ]
    )
    pair_model.fit(x_train, y_train)

    point_model = Pipeline(
        [
            ("scaler", StandardScaler()),
            (
                "reg",
                HistGradientBoostingRegressor(
                    max_depth=6,
                    learning_rate=0.08,
                    max_iter=250,
                ),
            ),
        ]
    )
    point_model.fit(xp_train, yp_train)

    train_acc = accuracy_score(y_train, pair_model.predict(x_train))
    val_acc = (
        accuracy_score(y_val, pair_model.predict(x_val)) if len(y_val) else float("nan")
    )
    print(f"train pairwise acc: {train_acc:.3f} (n={len(y_train)})")
    print(f"val   pairwise acc: {val_acc:.3f} (n={len(y_val)})")

    if len(yp_val):
        mae = mean_absolute_error(yp_val, point_model.predict(xp_val))
        print(f"val pointwise MAE: {mae:.2f} (n={len(yp_val)})")

    top1_pair, n_groups = eval_top1_pairwise(pair_model, layouts_rows)
    top1_point, _ = eval_top1_pointwise(point_model, layouts_rows)
    top1_pair_prop, n_prop = eval_top1_pairwise(
        pair_model, layouts_rows, proposals_only=True
    )
    top1_point_prop, _ = eval_top1_pointwise(
        point_model, layouts_rows, proposals_only=True
    )
    print(f"val top-1 pairwise:           {top1_pair:.3f} (groups={n_groups})")
    print(f"val top-1 pointwise:          {top1_point:.3f} (groups={n_groups})")
    print(f"val top-1 pairwise proposals: {top1_pair_prop:.3f} (groups={n_prop})")
    print(f"val top-1 pointwise proposals:{top1_point_prop:.3f} (groups={n_prop})")

    # Product metric: sort among Auto-Rig proposals only.
    ridge = Pipeline(
        [
            ("scaler", StandardScaler()),
            ("reg", Ridge(alpha=1.0)),
        ]
    )
    ridge.fit(xp_train, yp_train)

    def pair_score(row: dict) -> float:
        # Tournament strength vs group is computed in eval; for single-row export use
        # pointwise ridge as the deployable scorer.
        return float(ridge.predict([layout_features(row)])[0])

    def hgb_score(row: dict) -> float:
        return float(point_model.predict([layout_features(row)])[0])

    q_ridge = eval_ranking_quality(pair_score, layouts_rows, proposals_only=True)
    q_hgb = eval_ranking_quality(hgb_score, layouts_rows, proposals_only=True)
    print(
        f"proposals ridge  top1={q_ridge['top1']:.3f} top2={q_ridge['top2']:.3f} "
        f"regret={q_ridge['mean_regret']:.2f}"
    )
    print(
        f"proposals hgb    top1={q_hgb['top1']:.3f} top2={q_hgb['top2']:.3f} "
        f"regret={q_hgb['mean_regret']:.2f}"
    )

    # Prefer deployable ridge if top-2 within 5pts of HGB; else HGB pointwise.
    use_ridge = q_ridge["top2"] + 1e-9 >= q_hgb["top2"] - 0.05
    primary = "ridge" if use_ridge else (
        "pointwise" if top1_point_prop >= top1_pair_prop else "pairwise"
    )
    print(f"primary head: {primary}")

    # Export linear weights for a pure-Dart scorer (no TFLite required yet).
    scaler: StandardScaler = ridge.named_steps["scaler"]
    reg: Ridge = ridge.named_steps["reg"]
    # score = ((x - mean) / scale) · coef + intercept
    linear_coef = (reg.coef_ / scaler.scale_).tolist()
    linear_intercept = float(
        reg.intercept_ - float(np.dot(reg.coef_ / scaler.scale_, scaler.mean_))
    )

    args.out.mkdir(parents=True, exist_ok=True)
    ckpt = args.out / "ranker.joblib"
    joblib.dump(
        {
            "pairwise": pair_model,
            "pointwise": point_model,
            "ridge": ridge,
            "primary": primary,
            "slots": _SLOTS,
            "feature_dim": int(xp_train.shape[1]),
        },
        ckpt,
    )
    linear_path = args.out / "ridge_weights.json"
    linear_path.write_text(
        json.dumps(
            {
                "feature_dim": int(xp_train.shape[1]),
                "slots": list(_SLOTS),
                "coef": linear_coef,
                "intercept": linear_intercept,
                "metrics": q_ridge,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    # Also copy deployable weights into tracked assets path when quality is usable.
    assets = Path("assets/models/autorug_rank_ridge.json")
    assets.parent.mkdir(parents=True, exist_ok=True)
    assets.write_text(linear_path.read_text(encoding="utf-8"), encoding="utf-8")

    meta = {
        "train_pairwise_acc": train_acc,
        "val_pairwise_acc": val_acc,
        "val_top1_pairwise": top1_pair,
        "val_top1_pointwise": top1_point,
        "val_top1_pairwise_proposals": top1_pair_prop,
        "val_top1_pointwise_proposals": top1_point_prop,
        "proposals_ridge": q_ridge,
        "proposals_hgb": q_hgb,
        "primary": primary,
        "train_pairs": int(len(y_train)),
        "val_pairs": int(len(y_val)),
        "feature_dim": int(xp_train.shape[1]),
        "data": str(args.data),
        "layouts": len(layouts_rows),
    }
    (args.out / "metrics.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"Wrote {ckpt}")
    print(f"Wrote {linear_path}")
    print(f"Wrote {assets}")
    print(f"Wrote {args.out / 'metrics.json'}")


if __name__ == "__main__":
    main()
