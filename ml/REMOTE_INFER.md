# Remote YOLO sidecar (PC) — prototype on branch `remote`

Offload **object detection only** from the phone to this PC. Pose, camera preview,
and UI stay on-device. If the PC is unreachable, Scan falls back to TFLite / heuristics.

## 1. Start the PC server

```powershell
cd C:\Users\tempadmin\.gemini\antigravity\scratch\room_rig
ml\.venv\Scripts\python ml\remote_infer_server.py --host 0.0.0.0 --port 8787
```

Needs `ml/out/yolo_roomrig_best.pt` (or pass `--weights`).

Check health in a browser or:

```powershell
curl http://127.0.0.1:8787/health
```

Allow inbound TCP **8787** on Windows Firewall for private networks when using Wi‑Fi.

## 2. Phone setup

Same Wi‑Fi as the PC (or USB + `adb reverse tcp:8787 tcp:8787` then host `127.0.0.1:8787`).

Before Scan, open the pre-scan sheet:

- Enable **Use PC remote detect**
- Set host to `127.0.0.1:8787` when using `adb reverse`, or your PC LAN IP e.g. `192.168.254.102:8787` (no `http://`)

## 3. What success looks like

- PC terminal prints `detect XXXms boxes=N`
- Phone Scan honesty / logs mention remote when connected
- Laggy YOLO on-device should improve; boxes may trail slightly on weak Wi‑Fi

## 4. Failures to expect

| Symptom | Likely cause |
|--------|----------------|
| Falls back to TFLite | Wrong IP, firewall, server not running |
| High latency | Busy Wi‑Fi — lower detect rate is OK |
| Empty boxes | Model path wrong / conf too high |

This is an experiment branch — Hub / Rig / Bench are unchanged.
