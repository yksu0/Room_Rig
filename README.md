# Room Rig

Room Rig is a Flutter prototype for room scanning, room layout editing, and benchmark-style optimization.

The product goal is:
- scan a room
- generate 2D and 3D layouts
- list detected items in a sidebar for quick selection/highlighting
- support manual drag-and-drop arrangement in 2D
- support 3D orbit, tap-to-select, and deselect-on-second-tap in the room view
- support auto-arrangement optimized for airflow, lighting, or ergonomics

## Current Prototype Status

Implemented now:
- multi-screen app shell and state model
- scanner experience UI with progress/log simulation
- 2D grid canvas with furniture drag-and-drop
- 3D room view with orbit controls, zoom, and item highlighting
- benchmark screen with live room-model preview and simulation results
- score model for airflow, lighting, and ergonomics
- upgrades and optimization visualization screens

Not implemented yet:
- real camera/depth room scan pipeline
- real 3D model generation and rendering pipeline from camera capture
- detected-items sidebar fed by actual scan results
- true layout optimization engine that repositions objects automatically

See [plan.md](plan.md) for milestone details.

## Tech Stack

- Flutter
- flutter_svg
- google_fonts
- provider

## Run Locally

1. Install Flutter and ensure flutter is on PATH.
2. From project root, run:

```bash
flutter pub get
flutter analyze
flutter run
```

## Project Structure

- lib/main.dart: app shell and bottom navigation
- lib/models/app_state.dart: global state, scoring, room presets, and benchmark mode
- lib/models/room_model.dart: room presets and furniture model
- lib/screens/scanner_screen.dart: scanner prototype UI
- lib/screens/rig_customizer_screen.dart: 2D layout editor and 3D room orbit view
- lib/screens/benchmark_screen.dart: live room preview plus simulation and score results
- lib/screens/upgrades_screen.dart: upgrade catalog and boosts

## Quality Notes

- Analyzer status: clean (no issues at last check)
- Current implementation is still a prototype and contains mocked behavior for scan and simulation data
