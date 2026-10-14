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

## Train (pairwise RankNet-style head)

```powershell
python -m venv ml\.venv
ml\.venv\Scripts\pip install -r ml\autorug_rank\requirements.txt
ml\.venv\Scripts\python ml\autorug_rank\train_ranker.py --data ml/autorug_rank/smoke
```

Checkpoint → `ml/runs/autorug_rank/` (gitignored). Eval prints pairwise accuracy
on the val split vs simulator winners.

## Next milestones

1. Scale dump to thousands of rooms
2. Match ≥ ~85% top-1 vs current Auto-Rig on holdout
3. Export TFLite scorer and gate behind an Auto-Rig AI-sort flag
4. Optional: human preference fine-tune from Auto-Rig cycle UI
