# Room Rig YOLO → TFLite (WSL Ubuntu)

## Why

- Training on Windows produces `ml/out/yolo_roomrig_best.pt` (PyTorch).
- Flutter Scan needs `assets/models/yolo_roomrig.tflite`.
- Ultralytics TFLite export (`onnx2tf` chain) **fails on native Windows**.
- Convert inside **WSL Ubuntu** (Linux), then copy the `.tflite` into `assets/models/`.

Labels (18 classes) stay in sync via `ml/roomrig_classes.py` → `assets/models/yolo_roomrig_labels.txt`.

## One-time: install Ubuntu on WSL

### 0) Enable virtualization (required on this PC)

WSL2 needs **Virtual Machine Platform** + CPU virtualization in firmware.

**Admin PowerShell:**

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --install --no-distribution
```

Then **reboot**.

If install still errors with `HCS_E_HYPERV_NOT_INSTALLED` / “virtualization is not enabled”:

1. Reboot → enter BIOS/UEFI (Del / F2 / F10 — depends on board).
2. Enable **AMD-V** / **SVM Mode** (AMD) or **Intel VT-x** / **Virtualization Technology**.
3. Save, boot Windows, retry below.

### 1) Install Ubuntu

**Admin PowerShell (after reboot):**

```powershell
wsl --install -d Ubuntu
```

Open **Ubuntu** from the Start menu, create a Linux username/password when prompted.

Check:

```powershell
wsl -l -v
# should show Ubuntu Running / Stopped, VERSION 2
```

### Fallback if WSL / onnx2tf cannot finish (current status)

Local convert is **not succeeding** on this PC:
- Windows Ultralytics TFLite export: missing/broken `onnx2tf` chain
- WSL1 Ultralytics `.pt`→TFLite: package version clashes (`ml_dtypes` / TF)
- WSL1 `onnx2tf` on `yolo_roomrig_best.onnx`: YOLOv8 Detect `Mul_2` shape error (4 vs 8400) — known onnx2tf + YOLO issue; `-b 1` / `-ois` did not fix it

**What is already good (do not retrain):**
- `ml/out/yolo_roomrig_best.pt` — fine-tuned 18-class weights
- `ml/out/yolo_roomrig_best.onnx` — same weights as ONNX
- `assets/models/yolo_roomrig_labels.txt` — 18 Room Rig classes

**What is still wrong:**
- `assets/models/yolo_roomrig.tflite` — still the old ~3.3 MB COCO smoke stand-in (Sept), **not** Room Rig

### Google Colab convert (recommended next)

1. Open https://colab.research.google.com → New notebook  
2. Upload `ml/out/yolo_roomrig_best.pt`  
3. Run:

```python
!pip -q install ultralytics tensorflow
from ultralytics import YOLO
model = YOLO("yolo_roomrig_best.pt")
path = model.export(format="tflite", imgsz=640, int8=False)
print(path)
```

4. Download the produced `*_float32.tflite` (or similar)  
5. Replace `assets/models/yolo_roomrig.tflite` with that file (keep labels as-is)  
6. Rebuild/install the Flutter app and test Scan  

YouTube notify only fires on local script success — ignore it for Colab; you’ll know you’re done when the new `.tflite` size/date changes.

## Convert (run inside Ubuntu / via `wsl`)

This PC runs Ubuntu as **WSL1** (WSL2 hypervisor still blocked). Stock Ubuntu Python is **3.14** (no stable TF wheels) — the script uses **Miniconda Python 3.11**.

Repo path from WSL:

```text
/mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig
```

One-shot (preferred):

```powershell
wsl -d Ubuntu -- bash -lc "sed -i 's/\r$//' /mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig/ml/scripts/wsl_export_tflite.sh && bash /mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig/ml/scripts/wsl_export_tflite.sh"
```

Script: `ml/scripts/wsl_export_tflite.sh` — installs Miniconda + env `roomrig_export`, exports TFLite, copies to `assets/models/yolo_roomrig.tflite`.

Find the produced `.tflite` (often under `ml/runs/...` or next to the `.pt` / `*_saved_model/`):

```bash
find ml -name '*.tflite' -type f 2>/dev/null | head -20
```

Prefer a **float32** / non-int8 file sized roughly similar to a YOLOv8n head (not the old ~3.3 MB COCO smoke stand-in unless that is all you have).

Install into Flutter assets:

```bash
# Adjust SRC to the float32/saved_model tflite you found
SRC=ml/out/yolo_roomrig_best_saved_model/yolo_roomrig_best_float32.tflite
cp -f "$SRC" assets/models/yolo_roomrig.tflite
cp -f ml/out/yolo_roomrig_best.pt ml/out/ 2>/dev/null || true

# Refresh 18-class labels from Windows venv or WSL:
# (Windows)
#   ml\.venv\Scripts\python ml\install_roomrig_model.py
# or copy from ml/roomrig_classes.py order into:
#   assets/models/yolo_roomrig_labels.txt
```

From Windows after WSL export:

```powershell
ml\.venv\Scripts\python ml\install_roomrig_model.py
# only installs labels + tries export again on Windows — if tflite already
# copied into assets/models/, you can skip and just rebuild the app.
```

## After convert

1. Confirm `assets/models/yolo_roomrig.tflite` is **new** (timestamp / size ≠ old 3333264-byte smoke model).
2. Confirm `assets/models/yolo_roomrig_labels.txt` matches the 18 Room Rig classes.
3. Rebuild/install the Flutter app on the phone.
4. Smoke-test Scan (desk, chair, fan, etc.).

## Key paths

| What | Path |
|------|------|
| Trained weights | `ml/out/yolo_roomrig_best.pt` |
| ONNX fallback | `ml/out/yolo_roomrig_best.onnx` |
| Phone model | `assets/models/yolo_roomrig.tflite` |
| Phone labels | `assets/models/yolo_roomrig_labels.txt` |
| Class list source | `ml/roomrig_classes.py` (`ROOMRIG_CLASSES`) |
| WSL Python env | `ml/.venv_wsl/` (gitignored if present) |

## Do not

- Do not re-download the COCO smoke TFLite over a successful Room Rig export.
- Do not expect `train_roomrig_yolo.py` TFLite export to succeed on Windows.
- Do not plug in the phone until a real Room Rig `.tflite` is in `assets/models/`.

## Status log

| Date | Note |
|------|------|
| 2026-10-05 | Fine-tune done (mAP50 ~0.638). Windows TFLite export failed (`onnx2tf` missing). |
| 2026-10-05 | `wsl --install -d Ubuntu` failed: `HCS_E_HYPERV_NOT_INSTALLED` — Virtual Machine Platform / firmware virtualization not enabled. Doc updated; enable features + reboot (or BIOS SVM/VT-x), then retry Ubuntu. Colab is fallback. |
| 2026-10-05 | Admin DISM: WSL + VirtualMachinePlatform now **Enabled** (exit 0). Ubuntu register still failed until reboot — hypervisor not loaded yet. Next: reboot, then `wsl --install -d Ubuntu`. |
| 2026-10-05 | After reboot WSL2 still failed (`HCS_E_HYPERV_NOT_INSTALLED`). Workaround: `wsl --set-default-version 1` + install Ubuntu → **Ubuntu Stopped VERSION 1** (success). TFLite convert via WSL1. |
| 2026-10-05 | Pip failed: WSL DNS (`192.168.254.254`). Fixed via `ml/scripts/wsl_fix_dns.sh` → `8.8.8.8` + `generateResolvConf=false`. Retry export. |
| 2026-10-05 | Export reached onnx2tf then failed: Ultralytics AutoUpdate mixed TF 2.16 + tf_keras/TF 2.19 (`check_pinned` ImportError). Script now pins TF/tf_keras 2.16 and disables auto-update. Retrying. |
| 2026-10-05 | Full `.pt`→TFLite in WSL kept failing (onnxscript / ml_dtypes). Switch: export ONNX on Windows (`yolo_roomrig_best.onnx`), convert with `ml/scripts/wsl_onnx_to_tflite.sh`. |
| 2026-10-05 | onnx2tf failed on YOLOv8 Detect `Mul_2` shape broadcast. Retry with `-b 1`. Labels already refreshed (18 classes). |
| 2026-10-05 | **Colab export succeeded.** Installed `Downloads/yolo_roomrig_best.tflite` (~12.3 MB) → `assets/models/yolo_roomrig.tflite`. Next: rebuild Flutter app + phone Scan test. |
