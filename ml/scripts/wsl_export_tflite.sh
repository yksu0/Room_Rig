#!/usr/bin/env bash
# Run inside WSL Ubuntu:
#   bash ml/scripts/wsl_export_tflite.sh
#
# Uses Miniconda Python 3.11 — system Ubuntu Python 3.14 has no stable TensorFlow wheels.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
echo "REPO=$REPO"

# WSL1 often ships with broken DNS; pin public resolvers.
if [[ -w /etc/resolv.conf ]]; then
  printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf || true
fi

PT="${REPO}/ml/out/yolo_roomrig_best.pt"
if [[ ! -f "$PT" ]]; then
  echo "Missing $PT" >&2
  exit 1
fi

CONDA_ROOT="${HOME}/miniconda3"
CONDA_SH="${CONDA_ROOT}/etc/profile.d/conda.sh"
ENV_NAME="roomrig_export"

echo "=== apt (curl / ca-certificates) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates bzip2 >/tmp/roomrig_apt.log 2>&1 || {
  echo "apt failed; see /tmp/roomrig_apt.log" >&2
  tail -40 /tmp/roomrig_apt.log >&2
  exit 1
}

if [[ ! -f "$CONDA_SH" ]]; then
  echo "=== install Miniconda ==="
  INSTALLER=/tmp/miniconda.sh
  curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o "$INSTALLER"
  bash "$INSTALLER" -b -p "$CONDA_ROOT"
fi

# shellcheck disable=SC1090
source "$CONDA_SH"
conda config --set always_yes yes
# Non-interactive Anaconda ToS (required since 2024+ conda).
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
if ! conda env list | grep -qE "^${ENV_NAME}\\s"; then
  echo "=== create conda env ${ENV_NAME} (python 3.11) ==="
  conda create -n "$ENV_NAME" python=3.11 -y
fi
conda activate "$ENV_NAME"

echo "=== install export stack (pinned; avoid ultralytics TF upgrade clash) ==="
python -V
pip install -U pip wheel
# Pin TF + tf_keras together. Ultralytics AutoUpdate previously pulled TF 2.19
# over 2.16 and broke onnx2tf with ImportError check_pinned.
pip install "ultralytics==8.3.40" "onnx==1.17.0" onnxscript onnxruntime \
  "tensorflow==2.16.2" "tf_keras==2.16.0" \
  "onnx2tf==1.22.3" "sng4onnx>=1.0.1" "onnxslim>=0.1.31" "onnx_graphsurgeon>=0.3.26"
# Re-assert pins in case a transitive dep drifted
pip install --force-reinstall --no-deps "tensorflow==2.16.2" "tf_keras==2.16.0"

python -c "import torch, ultralytics, tensorflow as tf, tf_keras; print('torch', torch.__version__); print('ultralytics', ultralytics.__version__); print('tf', tf.__version__); print('tf_keras', tf_keras.__version__)"

echo "=== export TFLite ==="
# Disable Ultralytics auto-pip so it cannot upgrade TF mid-export
export YOLO_OFFLINE=1
export ULTRALYTICS_OFFLINE=1
python <<'PY'
from pathlib import Path
import shutil
import os
os.environ["YOLO_OFFLINE"] = "1"
from ultralytics import YOLO

repo = Path.cwd()
pt = repo / "ml" / "out" / "yolo_roomrig_best.pt"
out_dir = repo / "ml" / "out"
assets = repo / "assets" / "models"
assets.mkdir(parents=True, exist_ok=True)

model = YOLO(str(pt))
exported = Path(model.export(format="tflite", imgsz=640, int8=False))
print("export returned:", exported)

candidates = []
search_roots = [
    exported if exported.is_dir() else exported.parent,
    pt.parent,
    out_dir,
    repo / "ml" / "runs",
]
for root in search_roots:
    if root.is_dir():
        candidates.extend(root.rglob("*.tflite"))

def score(p: Path):
    name = p.name.lower()
    return (
        0 if "int8" in name else 1,
        1 if ("float32" in name or "float16" in name) else 0,
        p.stat().st_size,
    )

candidates = sorted(set(candidates), key=score, reverse=True)
if not candidates:
    raise SystemExit("No .tflite produced")

best = candidates[0]
print("chosen:", best, "size=", best.stat().st_size)
shutil.copy2(best, out_dir / "yolo_roomrig.tflite")
shutil.copy2(best, assets / "yolo_roomrig.tflite")
print("Installed", assets / "yolo_roomrig.tflite")
PY

echo "=== done ==="
ls -la assets/models/yolo_roomrig.tflite ml/out/yolo_roomrig.tflite
