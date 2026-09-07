# Model Assets

Expected detector path (gitignored — generate locally):

- `assets/models/yolo_roomrig.tflite`
- `assets/models/yolo_roomrig_labels.txt` (COCO-80 when using the smoke-test model)
- `assets/models/yolo_roomrig_target_labels.txt` (aspirational Room Rig classes; written by export script)

Until the `.tflite` file exists, Scan uses the approximate Luma/heuristic fallback.

## Generate / download

```powershell
python -m venv ml\.venv
ml\.venv\Scripts\pip install -r ml\requirements.txt
ml\.venv\Scripts\python ml\export_yolo_tflite.py
```

See `ml/README.md` for custom-train steps. Rebuild the app after the file appears.
