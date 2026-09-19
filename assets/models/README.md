# Model Assets

Expected detector path (gitignored weights — generate locally or via Colab):

- `assets/models/yolo_roomrig.tflite` — **Room Rig 18-class head** (trained + Colab/Linux TFLite export)
- `assets/models/yolo_roomrig_labels.txt` — must match model class count (**18** Room Rig names, same order as training)
- `assets/models/yolo_roomrig_target_labels.txt` — canonical 18 Room Rig names (training order)

When the Room Rig `.tflite` is present, Scan uses that detector. If missing or disabled, Scan falls back to luma / heuristic boxes.

Labels length is checked against the TFLite head so a mismatched pair will not silently misname boxes.

## After training

```powershell
ml\.venv\Scripts\python ml\smoke_test_detect.py
# Windows often cannot export TFLite — use Colab / WSL; see ml/TFLITE_EXPORT_WSL.md
# Then copy the .tflite to assets/models/yolo_roomrig.tflite and rebuild the app.
```

## Wireless phone logs (no extra phone load)

```powershell
# USB once: adb tcpip 5555   OR enable Wireless debugging
.\scripts\wireless_scan_logs.ps1 -PhoneIp 192.168.x.x
```

Streams `TfliteObjectDetector` infer ms / errors over Wi‑Fi while you walk the room unplugged.
