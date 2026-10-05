# Remote YOLO sidecar (PC) — prototype on branch `remote`

Offload **object detection only** from the phone to this PC. Pose, camera preview,
and UI stay on-device. If the PC is unreachable, Scan falls back to TFLite / heuristics.

## Status (2026-10-05)

Prototype **parked**. What landed on this branch:

- PC sidecar: `ml/remote_infer_server.py` (`GET /health`, `POST /v1/detect`, luma8 frames)
- Flutter client: `RemoteObjectDetector` + pre-scan **Use PC remote detect** toggle
- Release Android: `INTERNET` + cleartext so HTTP to the PC works
- Defaults aimed at USB smoke: host `127.0.0.1:8787` + `adb reverse tcp:8787 tcp:8787`
- Downscale upload to max 640px (full-res frames made remote feel ~1 FPS over USB)

**Findings from phone smoke (SM-G975F):**

- Sidecar *can* connect; PC infer was ~40–50ms once frames arrived.
- Scan still felt ~1 FPS. Most lag is **on-device pipeline** (ARCore sizing path,
  serial ingest / `setState`, preview) — remote YOLO does not run during ARCore
  sizing and cannot fix that UI path.
- Remote is a niche “better boxes when docked to PC” option, **not** a fix for
  phone Scan performance. Next real wins are elsewhere (manual room size / skip
  ARCore, decouple preview from detect), not more sidecar polish.

`test` / `main` are unchanged by this experiment; keep working there unless
reviving remote offload on purpose.

## 1. Start the PC server

```powershell
cd C:\Users\tempadmin\.gemini\antigravity\scratch\room_rig
ml\.venv\Scripts\python -u ml\remote_infer_server.py --host 0.0.0.0 --port 8787 --device cpu
```

Needs `ml/out/yolo_roomrig_best.pt` (or pass `--weights`).

Check health:

```powershell
curl http://127.0.0.1:8787/health
```

Allow inbound TCP **8787** on Windows Firewall for private networks when using Wi‑Fi.

## 2. Phone setup

Same Wi‑Fi as the PC (or USB + `adb reverse tcp:8787 tcp:8787` then host `127.0.0.1:8787`).

Before Scan, open the pre-scan sheet:

- Enable **Use PC remote detect** (defaults on on this branch)
- Set host to `127.0.0.1:8787` when using `adb reverse`, or your PC LAN IP (no `http://`)

## 3. What success looks like

- Phone log: `> Remote PC detect ready @ …`
- PC terminal prints `detect XXXms boxes=N` during **capture** (not ARCore sizing)
- Boxes may trail slightly on weak Wi‑Fi / USB

## 4. Failures to expect

| Symptom | Likely cause |
|--------|----------------|
| Falls back to TFLite | Wrong IP, firewall, server not running, release without INTERNET |
| Still ~1 FPS with remote OK | ARCore sizing / UI ingest — not YOLO; see Status above |
| High latency | Full-res upload (fixed by 640 downscale) or busy Wi‑Fi |
| Empty boxes | Conf / framing / gray luma vs training domain |

This is an experiment branch — Hub / Rig / Bench are unchanged.
