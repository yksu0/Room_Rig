# Catalog sprites

Optional top-down art for **Rig and Bench** furniture. Files are resolved by
`FurnitureItem.iconName` (same names as `RigCatalog` / `furnitureSvgFor`).

Bench CustomPainters load the same decoded sprites via `FurnitureSprites.paintPlanSprite`.
Bench 3D uses Rig's `RoomOrbit3DPainter` meshes.

## Naming

| Asset | Example |
| --- | --- |
| PNG (preferred) | `desk.png`, `fan.png` |
| SVG (fallback) | `desk.svg`, `fan.svg` |

Place files directly in this folder:

```
assets/sprites/
  desk.png
  chair.svg
  bed.svg
  fan.svg
  lamp.svg
  ac.svg
  wardrobe.svg
  plant.svg
  tv.svg
  heater.svg
  floorLamp.svg
  ceilingLight.svg
  intake.svg
  exhaust.svg
  purifier.svg
  lightBar.svg
  monitorArm.svg
  cableTray.svg
  mat.svg
  smartBlinds.svg
  …
```

## Resolution order

1. `assets/sprites/{iconName}.png`
2. `assets/sprites/{iconName}.svg`
3. Built-in procedural `FurnitureShapes` / inline SVG

Warm + decode via `FurnitureSprites.warmCache` in `main.dart` so both Rig cells
and Bench painters see sprites on first frame.

## Art tips

- Top-down plan view, square canvas (e.g. 128×128 or 256×256).
- Transparent background; keep silhouettes readable at ~24–48 px on screen.
- SVG `currentColor` / single-fill shapes tint cleanly via `ColorFilter`.
