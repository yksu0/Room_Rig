#!/usr/bin/env python3
"""Room Rig remote YOLO sidecar — run on the PC, phone POSTs luma frames.

Usage (from repo root, ML venv):
  ml\\.venv\\Scripts\\python ml\\remote_infer_server.py
  ml\\.venv\\Scripts\\python ml\\remote_infer_server.py --host 0.0.0.0 --port 8787 \\
      --weights ml/out/yolo_roomrig_best.pt

Protocol:
  GET  /health  -> JSON { ok, model, device, classes }
  POST /v1/detect
       Headers: X-Frame-Width, X-Frame-Height, X-Frame-Format: luma8
       Body: raw grayscale bytes (width*height)
       -> JSON { detections: [{ label, confidence, left, top, width, height }] }
         boxes normalized 0..1 relative to the frame

Phone keeps ARCore/camera/UI local; this only offloads detection.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np

ML_DIR = Path(__file__).resolve().parent
REPO = ML_DIR.parent
DEFAULT_WEIGHTS = ML_DIR / "out" / "yolo_roomrig_best.pt"

_model = None
_device = "cpu"
_names: dict[int, str] = {}


def _load_model(weights: Path, device: str):
    global _model, _device, _names
    from ultralytics import YOLO

    if not weights.exists():
        raise FileNotFoundError(f"Missing weights: {weights}")
    _model = YOLO(str(weights))
    _device = device
    # Warm-up
    dummy = np.zeros((640, 640, 3), dtype=np.uint8)
    _model.predict(dummy, imgsz=640, device=device, verbose=False)
    names = getattr(_model, "names", None) or {}
    if isinstance(names, dict):
        _names = {int(k): str(v) for k, v in names.items()}
    else:
        _names = {i: str(n) for i, n in enumerate(names)}
    print(f"Loaded {weights} device={device} classes={len(_names)}")


def _luma_to_bgr(buf: bytes, width: int, height: int) -> np.ndarray:
    expected = width * height
    if len(buf) < expected:
        raise ValueError(f"short frame: got {len(buf)} need {expected}")
    gray = np.frombuffer(buf[:expected], dtype=np.uint8).reshape((height, width))
    # Ultralytics expects HxWx3
    return np.stack([gray, gray, gray], axis=-1)


def _run_detect(frame_bgr: np.ndarray, conf: float = 0.35) -> list[dict]:
    assert _model is not None
    h, w = frame_bgr.shape[:2]
    t0 = time.perf_counter()
    results = _model.predict(
        frame_bgr,
        imgsz=640,
        conf=conf,
        device=_device,
        verbose=False,
    )
    ms = (time.perf_counter() - t0) * 1000.0
    out: list[dict] = []
    if not results:
        return out
    r0 = results[0]
    boxes = getattr(r0, "boxes", None)
    if boxes is None or boxes.xyxy is None:
        return out
    xyxy = boxes.xyxy.cpu().numpy()
    confs = boxes.conf.cpu().numpy()
    clss = boxes.cls.cpu().numpy().astype(int)
    for i in range(len(xyxy)):
        x1, y1, x2, y2 = xyxy[i].tolist()
        label = _names.get(int(clss[i]), str(int(clss[i])))
        left = max(0.0, x1 / w)
        top = max(0.0, y1 / h)
        width = max(0.0, (x2 - x1) / w)
        height = max(0.0, (y2 - y1) / h)
        out.append(
            {
                "label": label,
                "confidence": float(confs[i]),
                "left": float(left),
                "top": float(top),
                "width": float(min(1.0 - left, width)),
                "height": float(min(1.0 - top, height)),
            }
        )
    print(f"detect {ms:.0f}ms boxes={len(out)}", flush=True)
    return out


class Handler(BaseHTTPRequestHandler):
    conf_threshold = 0.35

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, X-Frame-Width, X-Frame-Height, X-Frame-Format",
        )
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if self.path.rstrip("/") == "/health":
            self._send_json(
                200,
                {
                    "ok": _model is not None,
                    "model": "yolo_roomrig",
                    "device": _device,
                    "classes": len(_names),
                    "names": [ _names[i] for i in sorted(_names.keys()) ],
                },
            )
            return
        self._send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") != "/v1/detect":
            self._send_json(404, {"ok": False, "error": "not_found"})
            return
        if _model is None:
            self._send_json(503, {"ok": False, "error": "model_not_loaded"})
            return
        try:
            width = int(self.headers.get("X-Frame-Width", "0"))
            height = int(self.headers.get("X-Frame-Height", "0"))
            fmt = (self.headers.get("X-Frame-Format") or "luma8").lower()
            length = int(self.headers.get("Content-Length", "0"))
            if width <= 0 or height <= 0 or length <= 0:
                self._send_json(400, {"ok": False, "error": "bad_headers"})
                return
            raw = self.rfile.read(length)
            if fmt != "luma8":
                self._send_json(400, {"ok": False, "error": "unsupported_format"})
                return
            frame = _luma_to_bgr(raw, width, height)
            dets = _run_detect(frame, conf=self.conf_threshold)
            self._send_json(200, {"ok": True, "detections": dets})
        except Exception as e:
            self._send_json(500, {"ok": False, "error": str(e)})


def main() -> int:
    parser = argparse.ArgumentParser(description="Room Rig remote YOLO sidecar")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--device", default="", help="cuda:0 / cpu (auto if empty)")
    parser.add_argument("--conf", type=float, default=0.35)
    args = parser.parse_args()

    import torch

    device = args.device or ("0" if torch.cuda.is_available() else "cpu")
    _load_model(args.weights, device)
    Handler.conf_threshold = args.conf

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Room Rig remote infer listening on http://{args.host}:{args.port}")
    print("GET /health   POST /v1/detect")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
