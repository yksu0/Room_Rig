# Where to pick models (CC0 / clear license)

Prefer **`.glb`** (or `.gltf` + textures). Room Rig maps files in `lib/services/gltf_catalog.dart`.

## Furniture (already mostly covered)

| Item | Best source | Notes |
|------|-------------|--------|
| Desk, chair, bed, sofa, shelf, wardrobe, lamps, plant, TV, door frame, window | [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit) | CC0, low-poly, self-contained GLB |
| Extra interior props | [Quaternius Ultimate House Interior](https://quaternius.com/packs/ultimatehomeinterior.html) | CC0, glTF/FBX |

## HVAC / airflow — wired in `assets/gltf/hvac/`

| Rig icon | File in repo | Source |
|----------|--------------|--------|
| **ac** | `air_condition.glb` (trial) / `ac_condenser.glb` (fallback) | [Sketchfab – Air conditioning (CC-BY)](https://skfb.ly/6SuD9) · fallback [3dassets condenser](https://3dassets.dev/assets/cyberpunk-apartment-and-neon-block-aircon-condenser-bo-b44b253e) |
| **intake** / **exhaust** | `vent.glb` (trial, ~7 MB) / `extract_fan_grille.glb` (fallback) | Sketchfab download · fallback [3dassets grille](https://3dassets.dev/assets/cyberpunk-apartment-and-neon-block-fan-grille-0c64ed5b) |
| **fan** | `fan.glb` (trial, ~18 MB) / `stand_fan.glb` (fallback) | Sketchfab download · fallback [3dassets balloon fan](https://3dassets.dev/assets/hot-air-balloon-festival-balloon-inflation-fan-71e7967c) |
| **purifier** | `air_scrubber.glb` | [3dassets – Air Scrubber](https://3dassets.dev/assets/cyberpunk-apartment-and-neon-block-air-scrubber-unit-5544e0ee) |
| **heater** | `radiator.glb` | [3dassets – Radiator](https://3dassets.dev/assets/dental-practice-and-surgery-radiator-019b3a52) |

### Optional higher-detail packs (also downloaded)

| Folder | Source |
|--------|--------|
| `exterior_aircon_unit/` | [Poly Haven – Exterior Aircon Unit](https://polyhaven.com/a/exterior_aircon_unit) (glTF 1k) |
| `modular_airduct_rectangular_01/` | [Poly Haven – Modular Airduct](https://polyhaven.com/a/modular_airduct_rectangular_01) |

Point `gltf_catalog.dart` at these if you want textured Poly Haven meshes instead of the compact GLBs.

### Other good CC0 / clear-license finds (not wired)

| Want | Link |
|------|------|
| Quaternius AC | [Poly Pizza](https://poly.pizza/m/amFuyE3IF6) |
| Quaternius Vent | [Poly Pizza](https://poly.pizza/m/UDFcnJ0U73) |
| Pedestal / standing fan | [Sketchfab – standing fan (downloadable)](https://sketchfab.com/search?q=standing+fan&type=models&features=downloadable) — **confirm CC0/CC-BY + glTF/GLB** before drop-in. Kenney only ships [ceilingFan](https://kenney.nl/assets/furniture-kit). Prefer Poly Pizza / Quaternius CC0 when a true pedestal appears. |

### Wall cuts (shell openings)

| Kind | Icons | Shell behavior |
|------|-------|----------------|
| **through** | door, window, smartBlinds | Full hole; exterior / glass / daylight |
| **niche** | ac, intake, exhaust | Tight recess + opaque grille — **no** sky hole |
| **none** | fan, purifier, heater (floor) | Model only; no wall cut |

Cut size = furniture footprint along the wall + `wallCutPadMeters` (~1.5–2 cm) in `gltf_catalog.dart`.

### Download tips

1. Prefer **under ~5 MB** GLB for mobile (the wired 3dassets files are &lt;120 KB each).
2. Poly Haven: `python scripts/download_polyhaven_gltf.py` (browser User-Agent required).
3. Keep glTF folders together (`.gltf` + `.bin` + `textures/`), or re-export a single GLB from Blender.

## Room shell materials

| Surface | Source |
|---------|--------|
| Wood floor / plaster walls | [Poly Haven textures](https://polyhaven.com/textures) (CC0) — already using `wood_floor` + `plastered_wall` |
