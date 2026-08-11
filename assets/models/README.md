# Model Assets

Place on-device detection models in this folder.

Expected path used by the scanner pipeline:
- `assets/models/yolo_roomrig.tflite`

Until that file is present, Room Rig uses `LumaStructureObjectDetector`
(contrast blobs → desk / chair / window / door labels) via the hybrid fallback.

Optional labels file (future):
- `assets/models/yolo_roomrig_labels.txt`
