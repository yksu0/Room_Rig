# Extra datasets — boost weak classes (fan / ac / blinds / vent)

Skip butane heaters. Detector class slot is **`vent`** (maps to intake in Rig), not heater.

Format: Roboflow → Download → **YOLOv8**

## Extract these

| Folder | Link | Map to |
|--------|------|--------|
| `ml/datasets/extra/fan/` | https://universe.roboflow.com/object-detection-bwxix/ceiling-fan-yolo-retrain | fan → `fan` |
| `ml/datasets/extra/fan/` (also OK) | https://universe.roboflow.com/object-detection-bwxix/ceilfan200 | fan → `fan` |
| `ml/datasets/extra/ac/` | https://universe.roboflow.com/yolo-uv06o/air-conditioning-dataset | `air_conditioning` → `ac` |
| `ml/datasets/extra/ac/` (more) | https://universe.roboflow.com/dataset-hvac/renovia-test1 | climatiseur / AC → `ac` |
| `ml/datasets/extra/blinds2/` | https://universe.roboflow.com/cv-project-j10ka/interior-designs | `curtain` → `blinds` |
| `ml/datasets/extra/vent/` | https://universe.roboflow.com/shun-x1tqo/air-vent-hole-v2 | `Air-Vent-Hole` → `vent` |
| ~~air-inlet-outlet~~ | skipped — Roboflow project export is empty (not a local download error) | — |

Optional HVAC mix (vents + equipment): https://universe.roboflow.com/boltdash/hvac_eq (`damper` → `vent`, `fan` → `fan`)

## Do not use

- Butane / cabinet heater sets — skipped in favor of vents

## Blinds (still weak after fine-tune)

Val mAP50 for `blinds` was ~0.20 after the last fine-tune. Prefer more curtain/blinds boxes before another train pass. Existing sources: `ml/datasets/extra/blinds/` + `blinds2/`. Do **not** restart from scratch — merge more blinds-only data then fine-tune from `ml/out/yolo_roomrig_best.pt` with `lr0=0.001`.
