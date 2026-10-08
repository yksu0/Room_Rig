# 3D model assets (`model` branch)

Real meshes for Rig **Model** view and Bench mesh-aware sims.

## Furniture (Kenney · CC0)

Kenney [Furniture Kit](https://kenney.nl/assets/furniture-kit) GLBs, mirrored via
[kenney_assets-classified](https://github.com/lateralus426/kenney_assets-classified).

Mapped in `lib/services/gltf_catalog.dart` with **mesh profiles** used by:

- Airflow particle / voxel collision heights
- Lighting occluders (hard shadows + glass transmittance)

## Room materials (Poly Haven · CC0)

- `wood_floor_diff.jpg` — floor albedo  
- `plaster_wall_diff.jpg` — wall albedo  

## Viewer

`assets/scene/room_viewer.html` builds:

- Exterior ground + sky (outside visible through openings)
- Wall segments with **door/window cutouts** + glass panes + daylight spots
- Instanced Kenney furniture from the live Rig layout
