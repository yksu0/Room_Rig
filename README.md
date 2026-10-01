# Room Rig

Flutter app that treats an indoor room like a PC build: **layout → score → optimize**.

**Core loop (demo-ready):** Hub → Rig → Bench → Upgrades  
**Optional:** Scan seeds a layout when the camera cooperates.

## What works now

- **Hub** — presets, manual rooms, My Rooms, score rings (`ROUGH EST.` / `BENCH OK`), checkpoints / history / compare (local builds)
- **Rig** — 2D drag + snap/collision, 3D orbit + MOVE, Place ghosts from Upgrades, Auto-Rig, undo
- **Bench** — airflow / lighting / ergonomics / spatial sims on the live Rig layout; My Room → Improved compare; Apply with conflict + no-op gates
- **Upgrades** — catalog → ghost on Rig → Place; boosts feed scores
- **Scan (approximate)** — Room Rig 18-class YOLO when `yolo_roomrig.tflite` is bundled; otherwise luma heuristics. Manual / walk / preset room size; ARCore (opt-in) or visual tracking for the minimap.

## Honest limits (say this in a presentation)

- Scan is **not** full AR SLAM or survey-grade depth — pose is ARCore (opt-in) or visual odometry; room size is preset, walk-measured, or manual
- Bench Airflow / Lighting / Ergonomics are **coarse heuristics** (voxel field, 2D lux proxy, clearance paths) — not CFD / radiosity / motion capture. Calibration notes: `assets/bench/`
- Pre-Bench Hub scores are impact estimates until you run Bench
- Upgrades prices/boosts are authored constants for the prototype
- ML weights under `assets/models/` are for **Scan detection only**, not Bench scoring

## Professor demo (no camera)

1. Hub → **Demo** → loads Gaming Setup → Rig  
2. Drag one item  
3. Bench → **Simulate** (My Room → Improved) → **Apply**  
4. Hub shows **BENCH OK**  
5. Optional: Upgrades → Place on Rig  

## Run

```bash
flutter pub get
flutter run
```

Phone install example:

```bash
flutter build apk --debug
flutter install -d <deviceId> --debug
```

Optional YOLO smoke weights (gitignored): see `ml/README.md` and `assets/models/README.md`.

## Stack

Flutter, Provider, camera, tflite_flutter, flutter_svg, google_fonts, share_plus, shared_preferences

## Layout

- `lib/main.dart` — tab shell  
- `lib/models/app_state.dart` — rooms, scores, persistence  
- `lib/screens/` — Hub, Scan, Rig, Bench, Upgrades  
- `lib/services/` — scan pipeline, Bench sims/optimizers, share/compare  
- `test/` — unit/widget coverage for layout, scan, Bench, Place ghosts  

## Status note

This README matches the current prototype. An **18-class Room Rig YOLO** detector
is bundled for Scan when `assets/models/yolo_roomrig.tflite` is present; remaining
Scan milestones are pose/depth honesty and weak classes (e.g. blinds). Soft Auto-Rig
clearances (sofa↔TV, wardrobe swing, side-light) and Hub ROUGH EST / BENCH OK honesty
are in place.
