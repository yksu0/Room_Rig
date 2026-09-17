# Room Rig — local YOLO → TFLite workspace

Scripts here are tracked; heavy outputs are gitignored (`ml/.venv/`, `ml/out/`, `assets/models/*.tflite`).

## One-shot setup (Windows PowerShell)

```powershell
python -m venv ml\.venv
ml\.venv\Scripts\pip install -r ml\requirements.txt
ml\.venv\Scripts\python ml\export_yolo_tflite.py
```

What the script does:

1. Tries Ultralytics TFLite/LiteRT export (works on **Linux/macOS**; recent Ultralytics blocks LiteRT export on Windows).
2. If export fails, downloads a public YOLOv8 COCO TFLite (~3.3 MB) from  
   [surendramaran/YOLOv8-TfLite-Object-Detector](https://github.com/surendramaran/YOLOv8-TfLite-Object-Detector).
3. Writes:
   - `assets/models/yolo_roomrig.tflite` (gitignored) — **COCO-80 smoke weights**
   - `assets/models/yolo_roomrig_labels.txt` — COCO-80 (must match the smoke head)
   - `assets/models/yolo_roomrig_target_labels.txt` — aspirational Room Rig classes for a **future** custom train

Then rebuild/install the Flutter app. Scan should report **COCO YOLO (smoke test)** when the asset loads.

## Note on classes

Smoke-test weights are **COCO-80** (chair, couch, bed, tv, …). The Flutter app remaps those labels into Rig icons (`scan_layout_converter.dart`). They are **not** a custom furniture set (no dedicated `desk` / `ac` / `fan` head).

### Training a custom Room Rig head (not done in-repo)

1. Collect / label images with `yolo_roomrig_target_labels.txt` classes.
2. Train YOLOv8 (or similar) on that dataset (GPU recommended).
3. Export TFLite and replace `yolo_roomrig.tflite` + swap labels file to the Room Rig list.
4. Keep honesty copy updated when the detector is no longer COCO smoke.

Until that lands, COCO + remap + luma heuristics is the honest Scan path.
