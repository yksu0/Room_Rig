# Where to pick models (CC0 / clear license)

Prefer **`.glb`** (or `.gltf` + textures). Room Rig maps files in `lib/services/gltf_catalog.dart`.

## Furniture (already mostly covered)

| Item | Best source | Notes |
|------|-------------|--------|
| Desk, chair, bed, sofa, shelf, wardrobe, lamps, plant, TV, door frame, window | [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit) | CC0, low-poly, self-contained GLB |
| Extra interior props | [Quaternius Ultimate House Interior](https://quaternius.com/packs/ultimatehomeinterior.html) | CC0, glTF/FBX |

## HVAC / airflow — wired in `assets/gltf/hvac/`

| Rig icon | File in repo | Source (CC0) |
|----------|--------------|--------------|
| **ac** | `ac_condenser.glb` | [3dassets – Aircon Condenser](https://3dassets.dev/assets/cyberpunk-apartment-and-neon-block-aircon-condenser-bo-b44b253e) |
| **intake** / **exhaust** | `extract_fan_grille.glb` | [3dassets – Extract Fan and Grille](https://3dassets.dev/assets/cyberpunk-apartment-and-neon-block-fan-grille-0c64ed5b) |
| **fan** | `stand_fan.glb` | [3dassets – Balloon Inflation Fan](https://3dassets.dev/assets/hot-air-balloon-festival-balloon-inflation-fan-71e7967c) (floor cage fan; swap for a pedestal fan when you find one) |
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
| Pedestal / standing fan | [Sketchfab search](https://sketchfab.com/search?q=standing+fan&type=models&features=downloadable) — confirm license + glTF |

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
