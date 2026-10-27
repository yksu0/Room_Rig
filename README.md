# Room Rig

Flutter app that treats an indoor room like a PC build: **layout → score → optimize**.

**Core loop (demo-ready):** Hub → Room → Benchmark (nav order: Hub · Room · Scan · Benchmark)  
**Optional:** Scan seeds a layout when the camera cooperates.

## What works now

- **Hub** — presets, manual rooms, My Rooms, score rings (`ROUGH EST.` / `BENCHMARK OK`), checkpoints / history / compare (local builds)
- **Room** — 2D drag + snap/collision, 3D orbit + MOVE, Items drawer / Place, Auto-Rig, undo
- **Benchmark** — airflow / lighting / ergonomics / spatial sims on the live Room layout; My Room → Improved compare; Apply with conflict + no-op gates; **Community** feed (publish / rate / clone / compare; guest browse)
- **Scan (approximate)** — Room Rig 18-class YOLO when `yolo_roomrig.tflite` is bundled; otherwise luma heuristics. Manual / walk / preset room size; ARCore (opt-in) or visual tracking for the minimap.
- **Storefront** — [`site/`](site/) on Vercel (`roomrig.vercel.app`): product pages, auth, GitHub Releases download entry, admin stub. Product use is the **Android APK**, not Flutter web.

## Honest limits (say this in a presentation)

- Scan is **not** full AR SLAM or survey-grade depth — pose is ARCore (opt-in) or visual odometry; room size is preset, walk-measured, or manual
- Benchmark Airflow / Lighting / Ergonomics are **coarse heuristics** (voxel field, 2D lux proxy, clearance paths) — not CFD / radiosity / motion capture. Calibration notes: `assets/bench/`
- Pre-Benchmark Hub scores are impact estimates until you run Benchmark
- Prices are mid-market PH estimates (`est. ₱`) — basis and verify-with terms ship in `assets/PRICE_SOURCES.md`; boosts are authored constants
- ML weights under `assets/models/` are for **Scan detection only**, not Benchmark scoring

## Professor demo (no camera)

1. Hub → **Demo** → loads Gaming Setup → Room  
2. Drag one item  
3. Benchmark → **Simulate** (My Room → Improved) → **Apply**  
4. Hub shows **BENCHMARK OK**  

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
- `lib/screens/` — Hub, Room, Scan, Benchmark, Profile  
- `lib/services/` — scan pipeline, Benchmark sims/optimizers, share/compare  
- `test/` — unit/widget coverage for layout, scan, Benchmark, Place ghosts  

## Status note

This README matches the current prototype. An **18-class Room Rig YOLO** detector
is bundled for Scan when `assets/models/yolo_roomrig.tflite` is present; remaining
Scan milestones are pose/depth honesty and weak classes (e.g. blinds). Soft Auto-Rig
clearances (sofa↔TV, wardrobe swing, side-light) and Hub ROUGH EST / BENCH OK honesty
are in place.
