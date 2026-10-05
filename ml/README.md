# Room Rig — local YOLO → TFLite workspace

Scripts here are tracked; heavy outputs are gitignored (`ml/.venv/`, `ml/out/`, `ml/datasets/`, `ml/runs/`, `assets/models/*.tflite`).

**Windows TFLite export fails** (onnx2tf). Convert with WSL Ubuntu — see **[TFLITE_EXPORT_WSL.md](TFLITE_EXPORT_WSL.md)** for install + convert steps and paths.

## Train a Room Rig detector (recommended)

Uses **Ultralytics HomeObjects-3K** (~2.7k indoor photos), remapped into
`yolo_roomrig_target_labels.txt` class ids, then fine-tunes **YOLOv8n** on GPU.

```powershell
python -m venv ml\.venv
ml\.venv\Scripts\pip install -r ml\requirements.txt
ml\.venv\Scripts\pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124

# One-shot: wait for dataset zip if still downloading, remap, train, install assets
ml\.venv\Scripts\python ml\wait_build_train.py
```

Or step-by-step:

```powershell
# 1) Download + remap labels → ml/datasets/roomrig_yolo/
ml\.venv\Scripts\python ml\build_roomrig_dataset.py

# 2) Train + export TFLite into assets/models/
ml\.venv\Scripts\python ml\train_roomrig_yolo.py --epochs 35 --batch 16
```

Outputs:

- `assets/models/yolo_roomrig.tflite` — custom Room Rig head (when TFLite export works)
- `assets/models/yolo_roomrig_labels.txt` — **same order as target labels** (18 classes)
- `ml/out/yolo_roomrig_best.pt` — PyTorch checkpoint
- `ml/datasets/roomrig_yolo/coverage.txt` — which classes have training boxes

After extras are merged:

```powershell
ml\.venv\Scripts\python ml\merge_extra_datasets.py
ml\.venv\Scripts\python ml\train_roomrig_yolo.py --model ml\out\yolo_roomrig_homeobjects_best.pt --epochs 25 --batch 16 --lr0 0.001
ml\.venv\Scripts\python ml\smoke_test_detect.py
ml\.venv\Scripts\python ml\install_roomrig_model.py
```

### Class coverage honesty

HomeObjects covers a strong subset (door, window, desk←table, chair, bed, sofa, tv,
pc←laptop, lamp, wardrobe, plant). Classes that still need more labeled photos after
merge are mainly **vent / fan / ac / blinds**. See `ml/MISSING_CLASSES_DATASETS.md`
and `ml/fetch_weak_classes.py`. (Heaters stay Rig-manual — no detector class slot.)

## Smoke-test only (COCO-80, not Room Rig)

```powershell
ml\.venv\Scripts\python ml\export_yolo_tflite.py
```

That path writes COCO labels — do **not** mix with a Room Rig-trained head.

## Windows TFLite note

Ultralytics TFLite/LiteRT export is unreliable on Windows. Training still saves
`best.pt` + ONNX under `ml/out/`. If `.tflite` is missing after train, export on
Linux/WSL:

```bash
yolo export model=ml/out/yolo_roomrig_best.pt format=tflite imgsz=640
```

Then copy the `.tflite` to `assets/models/yolo_roomrig.tflite` and rebuild the app.
