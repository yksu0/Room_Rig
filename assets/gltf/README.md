# 3D model assets (`model` branch)

Real meshes for Rig **Model** view and Bench previews.

## Furniture (Kenney · CC0)

Kenney [Furniture Kit](https://kenney.nl/assets/furniture-kit) GLBs (self-contained materials), mirrored via [kenney_assets-classified](https://github.com/lateralus426/kenney_assets-classified).

Mapped in `lib/services/gltf_catalog.dart` (`desk`, `chair`, `bed`, `sofa`, …).

## Room materials (Poly Haven · CC0)

- `wood_floor_diff.jpg` — floor albedo  
- `plaster_wall_diff.jpg` — wall albedo  

## Viewer

`assets/scene/room_viewer.html` + bundled `three@0.128` compose the room shell (floor, walls, ceiling, moldings, lights) and instance furniture GLBs from the live Rig layout.
