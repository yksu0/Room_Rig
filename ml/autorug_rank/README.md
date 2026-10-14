# Auto-Rig layout ranker (stage 1)

Learn to **sort** Auto-Rig candidate layouts the way today's
`MultiObjectiveOptimizer` + domain simulators already score them.

This is **not** a furniture generator and does **not** need Kaggle floor-plan
images. Labels come from Room Rig itself.

## Schema (`layouts.jsonl`)

One JSON object per line:

| Field | Meaning |
| --- | --- |
| `room_id` | Synthetic room id |
| `layout_id` | Unique layout id within the dump |
| `grid_cols` / `grid_rows` | Room grid |
| `anchors` | Door / window poses |
| `weights` | Normalized airflow / lighting / ergonomics / spatial |
| `layout.items` | Furniture poses (`id`, `category`, `iconName`, `gridX/Y`, size, yaw) |
| `labels.overall` | Composite score (training target) |
| `labels.*` | Domain metrics + `collision_ok` + `proposal_tag` |
| `split` | `train` or `val` |

`pairs.jsonl` rows: `{room_id, weights, layout_a_id, layout_b_id, winner_id, split}`
where `winner_id` is the higher `labels.overall` (stage-1 distillation).

## Dump data

From repo root (uses live Dart optimizers / simulators):

```powershell
# Small committed smoke set (must use flutter test — Dart CLI lacks dart:ui)
flutter test tool/dump_autorug_rank_dataset.dart --dart-define=AUTORUG_SMOKE=true --dart-define=AUTORUG_OUT=ml/autorug_rank/smoke

# Larger local dump (gitignored under ml/datasets/)
flutter test tool/dump_autorug_rank_dataset.dart --dart-define=AUTORUG_ROOMS=80 --dart-define=AUTORUG_OUT=ml/datasets/autorug_rank
```

## Train (pairwise + pointwise)

```powershell
python -m venv ml\.venv
ml\.venv\Scripts\pip install -r ml\autorug_rank\requirements.txt
ml\.venv\Scripts\python ml\autorug_rank\train_ranker.py --data ml/autorug_rank/smoke
# Full dump:
ml\.venv\Scripts\python ml\autorug_rank\train_ranker.py --data ml/datasets/autorug_rank
```

Checkpoint → `ml/runs/autorug_rank/ranker.joblib` (gitignored). Eval prints pairwise
accuracy, pointwise MAE, top-1/top-2, and mean Hub regret. Training also writes
deployable `assets/models/autorug_rank_ridge.json`.

## On-device sort (Dart ridge)

Loaded in `main.dart`. Sorting stays **pipeline-by-default**; enable with:

```dart
AutoRigRanker.enabled = true;
// or: MultiObjectiveOptimizer.optimizeCandidates(..., useAiSort: true)
```

Latest val (40 rooms × 5 mixes, proposals only): pairwise ~0.87, ridge mean
regret ~1.4 Hub points, HGB top-2 ~0.76. Exact top-1 stays hard because Auto-Rig
proposals are near-tied — regret matters more than exact match.

## Next milestones

1. Grow dump / features to lift proposal top-1 and top-2
2. UI toggle for AI sort on Auto-Rig
3. Optional TFLite HGB/MLP if ridge plateaus
4. Optional: human preference fine-tune from Auto-Rig cycle UI
