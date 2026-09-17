#!/usr/bin/env bash
# Convert existing ONNX → TFLite in WSL (skips torch.onnx which is flaky).
# Prefer: export ONNX on Windows first, then run this.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
echo "REPO=$REPO"

if [[ -w /etc/resolv.conf ]]; then
  printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf || true
fi

ONNX=""
for c in \
  "$REPO/ml/out/yolo_roomrig_best.onnx" \
  "$REPO/ml/out/best.onnx" \
  "$REPO/ml/runs/roomrig/weights/best.onnx"
do
  if [[ -f "$c" ]]; then ONNX="$c"; break; fi
done

CONDA_SH="${HOME}/miniconda3/etc/profile.d/conda.sh"
# shellcheck disable=SC1090
source "$CONDA_SH"
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda activate roomrig_export

# If no ONNX yet, export it here with a torch that uses legacy exporter
if [[ -z "$ONNX" ]]; then
  echo "=== no ONNX on disk — exporting from best.pt (legacy ONNX) ==="
  PT="$REPO/ml/out/yolo_roomrig_best.pt"
  pip install -U pip wheel
  pip install "ultralytics==8.3.40" "onnx==1.16.1" "onnxscript==0.1.0" \
    "ml_dtypes==0.3.2" "numpy==1.26.4"
  python <<'PY'
from pathlib import Path
from ultralytics import YOLO
pt = Path("ml/out/yolo_roomrig_best.pt")
model = YOLO(str(pt))
# simplify=False avoids some onnxscript paths on older stacks
out = Path(model.export(format="onnx", imgsz=640, simplify=False, opset=12))
print("onnx:", out)
PY
  ONNX=$(find ml/out ml/runs -name '*.onnx' -type f | head -1)
fi

echo "ONNX=$ONNX"
test -f "$ONNX"

echo "=== install onnx2tf stack (pinned) ==="
pip install -U pip wheel
pip install "numpy==1.26.4" "ml_dtypes==0.3.2" \
  "tensorflow==2.16.2" "tf_keras==2.16.0" \
  "onnx==1.16.1" "onnxruntime==1.18.1" \
  "onnx2tf==1.22.3" "sng4onnx>=1.0.1" "onnxslim>=0.1.31" \
  "onnx_graphsurgeon>=0.3.26" "protobuf==3.20.3"

OUT_DIR="$REPO/ml/out/tflite_convert"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== onnx2tf convert ==="
# YOLOv8 Detect Mul broadcast: pin static NCHW input
onnx2tf -i "$ONNX" -o "$OUT_DIR" -b 1 -ois "images:1,3,640,640" -osd --non_verbose \
  || onnx2tf -i "$ONNX" -o "$OUT_DIR" -b 1 -ois "images:1,3,640,640" \
  || onnx2tf -i "$ONNX" -o "$OUT_DIR" -b 1 -ois "images:1,3,640,640" -onwdt


echo "=== pick float32 tflite ==="
python <<'PY'
from pathlib import Path
import shutil
repo = Path.cwd()
root = repo / "ml" / "out" / "tflite_convert"
assets = repo / "assets" / "models"
out_dir = repo / "ml" / "out"
cands = list(root.rglob("*.tflite"))
if not cands:
    raise SystemExit("no tflite from onnx2tf")

def score(p: Path):
    n = p.name.lower()
    return (0 if "int8" in n else 1, 1 if "float32" in n else 0, p.stat().st_size)

best = sorted(cands, key=score, reverse=True)[0]
print("chosen", best, best.stat().st_size)
shutil.copy2(best, out_dir / "yolo_roomrig.tflite")
shutil.copy2(best, assets / "yolo_roomrig.tflite")
print("Installed", assets / "yolo_roomrig.tflite")
PY

ls -la assets/models/yolo_roomrig.tflite
echo "=== done ==="
