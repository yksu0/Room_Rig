# Bench calibration

`calibration.json` documents the **honest model** for Airflow / Lighting / Ergonomics.

These benches are **rule-based heuristics** scored on furniture geometry.
They are **not** trained neural nets. Do not drop YOLO weights here.

| Domain | Model | Not |
| --- | --- | --- |
| Airflow | Coarse voxel force field + particles | CFD |
| Lighting | 2D lux proxy + soft occlusion | Radiosity |
| Ergonomics | Clearance, reach, grid paths | ISO lab / motion capture |
| Spatial | Floor-use / circulation estimate | Surveyed area |

Scan object detection (YOLO TFLite) is separate under `assets/models/`.

Golden layout fixtures live in:

- `lib/models/airflow_prototype.dart`
- `lib/models/lighting_prototype.dart`
- `lib/models/ergonomics_prototype.dart`
