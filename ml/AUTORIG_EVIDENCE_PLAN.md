# Auto-Rig Evidence Plan (Phase 1)

**Owner:** Rig ML  
**Status:** research + plan only (no training, no app code changes in this turn)  
**Repo paths claimed:** `ml/AUTORIG_EVIDENCE_PLAN.md`  
**Date:** 2026-10-30 (Asia/Manila)

Goal: every arrangement decision and Benchmark grade should eventually cite real data or standards, not only author opinion. This doc inventories what the app does today, marks what is unbacked, lists verified evidence sources, proposes a learned Auto-Rig, a re-grounded grading scheme, and a major **object-height** model for airflow/lighting.

---

## 1. Executive findings (short)

1. Auto-Rig is a **rules packer + multi-objective scorer**, not a generative layout model. Candidates come from domain optimizers; ranking is weighted Hub score (default) or a **distilled ridge** when "AI layout sort" is on.
2. The distilled model (`assets/models/autorug_rank_ridge.json`) is trained to imitate **today's simulator composite**, so it inherits every opinionated constant. Turning the toggle on does **not** ground decisions in external data.
3. Biggest unbacked / opinion-calibrated constants: Benchmark pass bars (`airflowPass=50.5`, `lightingPass=45`, `ergonomicsPass=58`, `deadZoneMax=0.695`, etc.), Hub composite penalties (`-25` hard conflict, `0.38` cluster), sofa–TV preferred `2.2` cells, many score blend weights inside simulators.
4. Partially backed (agency/practice citations already in code comments, not certification): OSHA window/desk glare angles; Appleton 1975 prospect–refuge; ~0.9 m aisle (ADA-adjacent residential habit); HVAC face clearance ~6–18 in practice.
5. Height today: **room** has `heightMeters`; furniture **world height** lives in `GltfCatalog.MeshProfile.heightMeters`. `FurnitureItem.height` is **plan depth (grid Y)**, not vertical size — easy to misread.
6. Airflow is **already 3D-ish** (AABB from floor to mesh height rasterized into voxels). Lighting is **2.5D** (XZ rays + height thresholds). Collision/Auto-Rig packing are pure **2D**.
7. Recommended next model path: keep hard clearance constraints; train a **learned energy / pairwise scorer** (or later ATISS-style placer) on research layouts + user prefs; use 3D-FRONT only under its **non-commercial research** license (or preference/app data for product).
8. Object height should become a first-class sim input: per-type heights + porosity, vertical cross-section vs source/receiver bands (ASHRAE 55 0.1 / 0.6 / 1.1 / 1.7 m), feature-flagged rollout.
9. Ownership: Rig App owns `lib/` models, catalog, UI, tests, schema defaults; Rig ML owns evidence tables, `ml/`, evaluation metrics, distillation/retrain recipes.
10. Phase 1 deliverable is this doc only.

---

## 2. Current Auto-Rig architecture

### 2.1 Entry points and toggle

| Piece | Where | Role |
| --- | --- | --- |
| Room Tools → Auto-Rig | `lib/screens/room_customizer_screen.dart` (~1137–1146) | SwitchListTile **"AI layout sort"**; sets `AutoRigRanker.enabled` |
| Ranker load | `lib/main.dart` (~55–57) | `await AutoRigRanker.load()` from asset JSON |
| Apply / cycle | `lib/models/app_state.dart` (~2883–2956) | `optimizeCandidates` → pick cursor → apply furniture; `cycleAutoRigAlternate` |
| Candidate pool | `lib/services/multi_objective_optimizer.dart` | Domain optimizers + rules pack → score → keep top 4 |
| Distilled scorer | `lib/services/autorug_ranker.dart` | Ridge linear score over fixed feature slots |
| Teacher labels | `lib/services/autorug_training_export.dart` + `tool/dump_autorug_rank_dataset.dart` | Dump layouts whose `labels.overall` = `MultiObjectiveOptimizer.scoreLayout` |
| Train | `ml/autorug_rank/train_ranker.py` | Pairwise + pointwise; deploy ridge weights |
| Asset | `assets/models/autorug_rank_ridge.json` | `feature_dim=124`, val top1≈0.31, top2≈0.51, mean_regret≈1.36 |

**Toggle semantics:** when `AutoRigRanker.enabled` is false (default), candidates sort by simulator Hub composite. When true **and** weights loaded, sort by ridge prediction; simulator metrics still attach for UI (`multi_objective_optimizer.dart` ~200–201, ~351–372). Generation path is unchanged — only ranking changes.

**Important:** Rig App currently claims `room_customizer_screen.dart` for UI work. This plan does not edit that file; references are read-only.

### 2.2 Pipeline (hard-coded path)

```
inventory + anchors + MultiObjectiveWeights
        |
        |- AirflowOptimizer.optimize
        |- LightingOptimizer.optimize
        |- ErgonomicsOptimizer.optimize
        |- SpatialOptimizer.optimize
        |- LayoutOptimizerCommon rules pack (work cluster, perimeter, HierarchicalLayout.enforce)
        |
        v
diverse candidate layouts (<=4 kept)
        |
        v
scoreLayout = sum w_i * domainScore - hardConflictPenalty - clusterPenalty
        |
        v (optional AI sort)
AutoRigRanker.score(features)  OR  scoreLayout
        |
        v
Best / Alternate #n applied to Room
```

Shared packing / geometry: `layout_optimizer_common.dart`, `hierarchical_layout.dart`, `item_placement_rules.dart`, `layout_collision.dart`, `comfort_heuristics.dart`, `placement_catalog.dart`.

### 2.3 Distilled model (teacher → student)

- **Teacher:** live Dart sims + `MultiObjectiveOptimizer.scoreLayout` (`autorug_training_export.dart` header; README).
- **Features:** weight norms, room size, collision_ok, inventory count, per-slot present/meanX/meanY/sinYaw/cosYaw/area, pairwise relative desk–chair / desk–window / …, yaw deltas (`autorug_ranker.dart` 12–26, 91–196; `train_ranker.py` `_SLOTS` + `layout_features`).
- **Labels:** `labels.overall` (pointwise); pairwise winner = higher overall.
- **Models tried:** sklearn Ridge (deployed) and HistGradientBoosting; ridge preferred if top-2 within ~5 pts of HGB (`train_ranker.py` ~405–412).
- **Limitation:** student cannot exceed teacher grounding. Preference fine-tune is listed as a future milestone in `ml/autorug_rank/README.md`, not implemented.

---

## 3. Rule and constant inventory

Legend for **Evidence today**:  
`code-cited` = comment already names a source (not app certification) · `calibrated` = tuned to demo voxel scores · `opinion` = author preference / no external cite · `partial` = practice number without primary standard pin.

### 3.1 Clearances and placement (`comfort_heuristics.dart`, `item_placement_rules.dart`, `placement_catalog.dart`)

| Constant | Value | File:line (approx) | Evidence today | Could back with |
| --- | --- | --- | --- | --- |
| `chairPullbackCells` | 0.95 cells ≈ **0.57 m** | `comfort_heuristics.dart:28` | `partial` — comment says practice, not ISO 9241-5; Panero-scale ~0.95 m does not fit 6×8 demo | Panero & Zelnik *Human Dimension & Interior Space* (knee/chair clear); BIFMA seating ranges; user sit tests |
| `doorApproachDepthCells` | 1.2 cells ≈ **0.72 m** | `comfort_heuristics.dart:35` | `partial` — "code-adjacent", not IBC | 2010 ADA Standards accessible route **36 in (915 mm)** continuous clear width (Access Board Ch.4 / §403); residential habit ≠ full ADA dwelling compliance |
| `hvacClearanceCells` | 0.55 cells ≈ **0.33 m / 13 in** | `comfort_heuristics.dart:44` | `partial` — comment "6–18 in" HVAC practice | Manufacturer throw clearances; ASHRAE diffuser guidance (product-specific) |
| `personRadiusCells` | 0.45 ≈ **0.27 m** | `comfort_heuristics.dart:50` | `opinion` | Anthropometry (Panero); not a code radius |
| `minAisleMeters` | **0.9 m** | `comfort_heuristics.dart:56` | `partial` — residential walkway target | ADA 36 in route; IBC egress widths (do **not** claim compliance) |
| `deskBedClearance` | **1.05** cells | `item_placement_rules.dart:57` | `partial` — "~42 in desk–furniture practice" | Interior layout guides; preference studies |
| `wallFlushTolerance` / `deskWallTolerance` | **0.35** | `item_placement_rules.dart:64–67` | `opinion` | 3D-FRONT wall-attachment priors |
| `sofaTvPreferred` / `Tolerance` | **2.2 ± 0.65** cells (~1.3 m ±0.4) | `item_placement_rules.dart:70–74` | `partial` — '~55" TV mid band ~2 m' | THX/SMPTE viewing-distance guidance; manufacturer TV size to distance charts |
| `wardrobeFrontClearance` | **1.1** cells | `item_placement_rules.dart:77` | `partial` — door swing | Door leaf width + approach (practice) |
| Placement zones / notes | enum + strings | `item_placement_rules.dart:24–210` | `code-cited` OSHA / Appleton / HVAC in header | Keep as soft priors; replace soft scores with data |
| Catalog clearances | front/back/side/vent per SKU | `placement_catalog.dart` ~165–370 | `opinion` / practice mix | Map each to Neufert / NKBA / BIFMA where applicable |

### 3.2 Behavioral scores (`comfort_heuristics.dart`)

| Score | Idea | Evidence today | Stronger backing |
| --- | --- | --- | --- |
| `doorProspectScore` | Seat can see entry | `code-cited` Appleton 1975 prospect–refuge; workplace practice | Environmental psychology replications; preference A/B in-app |
| `bedPrivacyFromDoor` | Bed off inbound door axis | `partial` — residential / CAADRIA-style solvers | Layout datasets; privacy preference studies |
| `windowSideLightScore` | Desk not square-on to window | `code-cited` [OSHA Computer Workstations eTools](https://www.osha.gov/etools/computer-workstations/workstation-environment) — display at right angles to windows | Keep; add glare lux thresholds from IES/EN |
| `hvacClearanceScore` | Furniture off vent/AC faces | `partial` practice | OEM clearances |

### 3.3 Hierarchical / packing rules (`hierarchical_layout.dart`, `layout_optimizer_common.dart`)

| Rule | Notes | Evidence |
| --- | --- | --- |
| `wallTol = 0.08` | Wall touch | `opinion` |
| Pin bed headboard, sofa–TV span, ceiling lights center, portable AC near window, PC vent nudge | Procedural | Mix of practice + demo fit |
| `workClusterIntegrityScore` penalties (−18…−28) | Monitor face, chair gap, bounds | `calibrated` / `opinion` |
| Desk long-edge along wall | Comment in `item_placement_rules` / optimizer | Practice; verify vs 3D-FRONT desk–wall stats |

### 3.4 Multi-objective Hub score (`multi_objective_optimizer.dart`)

| Piece | Value | Evidence |
| --- | --- | --- |
| Domain blend | `air*w_a + light*w_l + ergo*w_e (+ space)` | Weight mix is **user-facing preference**, OK as UX; not "truth" |
| Hard conflict penalty | **−25** | `opinion` |
| Work-cluster penalty scale | **0.38 × (100−cluster)** | `opinion` / calibrated |
| Max kept candidates | **4** | UX |

### 3.5 Benchmark grading (`benchmark_validator.dart`, `benchmark_score_copy.dart`)

Pass / fail thresholds (explicitly calibrated to 6×8 gaming reference room — see comments near `airflowPass`):

| ID | Threshold | Evidence today |
| --- | --- | --- |
| Circulation pass | **50.5** | `calibrated` — **no external standard** |
| Lighting exposure pass | **45.0** | `calibrated` |
| Ergonomics comfort pass | **58.0** | `calibrated` |
| Dead zone max | **0.695** | `calibrated` |
| Glare max | **0.55** | `calibrated` (unitless risk, not lux) |
| Path min | **0.45** | `calibrated` |
| Walkable min | **0.35** | `opinion` / calibrated |
| Spatial util pass | **55.0** | `calibrated` |
| Grade words Needs work / OK / Good / Strong | vs pass bar & 75/90 | `opinion` UX copy (`benchmark_score_copy.dart`) |

Honest UI already warns scores are rough estimates, not lab tests (`benchmark_score_copy.dart` blurbs).

### 3.6 Domain simulators (high level)

- **Airflow:** coarse voxel CFD-ish field + particles (`airflow_simulator.dart`); metrics circulation / deadZone / heatPocket / exitChannel / workZoneCooling / hvacClearance. Boxes use **mesh height** (see §6).
- **Lighting:** floor-plane lux grid + occluders (`lighting_simulator.dart`); taskIllumination, shadowRatio, glareRisk, sideLightScore, daylightReach. Height used as **threshold**, not full 3D ray.
- **Ergonomics:** desk/chair gap, reach, aisle, path A*, prospect/privacy (`ergonomics_simulator.dart`); comfort blend weights near ~429–436 are author-chosen.

---

## 4. Evidence catalog (verified sources only)

Sources below were checked via web search/fetch for this plan. Do **not** invent additional primary citations in product copy without opening the document.

### 4.1 Clearance / accessibility / anthropometry

| Source | What it supports | Caveat for Room Rig |
| --- | --- | --- |
| **2010 ADA Standards** — clear floor 30×48 in (§305); accessible route min **36 in** clear width, 32 in at short points ([Access Board guides](https://www.access-board.gov/ada/guides/chapter-3-clear-floor-or-ground-space-and-turning-space/), [Ch.4 routes](https://www.access-board.gov/ada/guides/chapter-4-accessible-routes/)) | Aisle / approach **targets** | App is not an accessibility certifier; most rooms are residential gaming setups |
| **Panero & Zelnik**, *Human Dimension & Interior Space* (Whitney, 1979) | Chair/desk anthropometry, reach | Classic reference; buy/cite edition used |
| **Neufert** *Architects' Data* | Furniture module sizes, clearances | Edition-dependent tables |
| **ANSI/BIFMA** seating / desk furniture standards | Adjustable seat height bands (commonly cited ~38–51 cm seat) | Office furniture, not bedrooms |
| **NKBA** kitchen guidelines | Work-aisle widths (kitchen-specific) | Only if kitchen classes added |

### 4.2 Lighting

| Source | Support |
| --- | --- |
| **EN 12464-1:2021** Table 34 (offices): writing/typing/reading **500 lx** maintained; filing 300 lx; drawing 750 lx | Task lux targets for desk score recalibration |
| **ANSI/IES RP-1-24** Office lighting recommended practice | US practice; do not paste EN numbers as "IES" |
| **OSHA eTools** Computer Workstations — monitors at right angles to windows | Already cited in code; keep |

### 4.3 Airflow / thermal

| Source | Support |
| --- | --- |
| **ANSI/ASHRAE Standard 55** (2020/2023): measurement heights **0.1, 0.6, 1.1 m** seated; **0.1, 1.1, 1.7 m** standing | Occupant bands for height-aware airflow / local discomfort |
| **ASHRAE 62.1** | Ventilation rates (whole-building; coarse for single-room toy CFD) |
| ENERGY STAR / CBE ceiling fan guides | Blade height ≥7 ft AFF, clearances | For ceiling-fan class if added |

### 4.4 Layout datasets and scene-synthesis papers

| Dataset / paper | Status / license note |
| --- | --- |
| **3D-FRONT** (Alibaba / Tao Bao) | Large furnished rooms; **scientific research only** — no commercialization of dataset, derivatives, or results used as external service ([license PDF](https://gw.alicdn.com/bao/uploaded/TB1ZJUfK.z1gK0jSZLeXXb9kVXa.pdf?file=TB1ZJUfK.z1gK0jSZLeXXb9kVXa.pdf)). **Cannot ship a product model trained only on 3D-FRONT.** |
| **Structured3D** | Available under its ToU; synthetic structured interiors |
| **SUNCG** | **Withdrawn / unavailable** (Planner5D dispute) — do not plan on it |
| **ScanNet** | Real scans; ToU; good for perception, weaker for "designed" furniture layouts |
| **Hypersim** (Apple) | CC BY-SA 3.0 for public release imagery; meshes may need source assets |
| **ATISS** (Paschalidou et al., NeurIPS 2021) | Autoregressive transformer over unordered 3D boxes; floor-plan conditioned |
| **SceneFormer** (Wang et al., 3DV 2021) | Transformer sequence of objects |
| **DiffuScene** (Tang et al., CVPR 2024 / arXiv:2303.14207) | Diffusion over unordered object attributes on 3D-FRONT |
| **LayoutGPT** et al. | LLM-conditioned layout — useful inspiration, not a drop-in |

### 4.5 In-app preference data (product-safe)

Collect (opt-in): Auto-Rig Best vs Alternate choices; Benchmark Apply accept/reject; manual drags after Auto-Rig; thumbs on explain lines; optional ranked A/B of two layouts. This is the **primary commercial training signal**.

---

## 5. Proposed learned Auto-Rig (after Phase 1)

### 5.1 Approach (recommended staged)

**Stage A — Constraint + learned ranker (near-term)**  
Keep `LayoutOptimizerCommon` / hierarchical hard rules as a **feasible set** generator (or widen with MCMC / random legal poses). Replace Hub-imitation ridge with a ranker trained on:

1. Preference pairs from users (Bradley–Terry / RankNet), and/or  
2. Research layouts mapped into app classes (**offline research only** if 3D-FRONT), and/or  
3. Hybrid: hard constraint violations as infinite loss; soft energy from data.

**Stage B — Generative placer (mid-term)**  
ATISS- or DiffuScene-style model over the app's ~18 icon classes + anchors (door/window/AC), conditioned on floor polygon and inventory multiset. Output yaw-snapped grid poses. Run through collision + clearance repair.

**Stage C — On-device**  
Distill to TFLite / small MLP or keep ridge/HGB JSON like today; always show constraint attributions in UI.

### 5.2 Class mapping (app ↔ datasets)

Map Kenney / Room Rig icons (`desk, chair, bed, sofa, shelf/bookshelf, wardrobe, table, tv, monitor, pc, lamp, floorLamp, plant, fan, ac, …`) to 3D-FRONT / 3D-FUTURE categories via a maintained table in `ml/`. Many dataset classes (nightstand, cabinet, …) collapse to `shelf`/`table`/`other`. Document many-to-one loss of nuance.

### 5.3 Validation metrics

| Metric | Purpose |
| --- | --- |
| Collision / OOB rate | Feasibility |
| Clearance compliance rate | Against evidence-backed thresholds |
| Category co-occurrence KL vs reference set | Distributional realism |
| FID/KID on top-down renders | Visual realism (research) |
| Hub regret vs current Auto-Rig | Regression guard |
| Human A/B win rate | Product north star |
| Explain fidelity | Attribution vs user-accepted reasons |

### 5.4 Per-placement explanation

1. **Constraint attribution:** which hard rule fired (desk–bed gap, vent blocked, …) with cited source id.  
2. **Nearest exemplars:** top-k training layouts (privacy-safe) with same inventory signature.  
3. **Feature attribution:** linear coef × feature (already natural for ridge) or SHAP on HGB; map slots to plain language.  
4. Never claim "ADA compliant" / "ASHRAE certified" — use "aligned with … guidance".

### 5.5 Re-grounded Benchmark scheme

| Factor | Proposed basis | Weight setting |
| --- | --- | --- |
| Circulation / dead air | Occupant-band mean speed proxies at ASHRAE 55 heights; dead fraction below draft threshold | Fit pass bar so "reference good room" corpus median passes; publish calibration note |
| Task light | Compare desk lux proxy to **500 lx** EN target (normalized 0–100) | Scale curve from sim units → lux proxy via one measured calibration room |
| Glare | OSHA geometry + optional luminance contrast later | Binary geometry gate + soft risk |
| Comfort / paths | Chair pull-back vs Panero/BIFMA band; aisle vs 0.9–0.915 m | Continuous scores |
| Conflicts | Unchanged hard fail | Weight infinite |
| Spatial | Walkable % + largest aisle vs ADA-adjacent width | |
| Grade words | Keep UX tiers but document numeric meaning | Weights from preference logistic regression once n≥N |

Every factor row in UI gets a `source_id` → short citation string from a frozen table (this doc → later `ml/evidence_sources.json`).

---

## 6. Object height (major)

### 6.1 Naming trap

| Field | Meaning |
| --- | --- |
| `FurnitureItem.width` / `.height` | **Plan footprint** in grid cells (X and **depth Z**). Not world Y. (`room_model.dart` FurnitureItem) |
| `RoomDimensions.heightMeters` / `RoomScale.defaultHeightMeters=2.7` | Ceiling height |
| `MeshProfile.heightMeters` | **World vertical extent** of the asset (`gltf_catalog.dart`) |
| `LightingOccluder.height` | World Y used as occlusion threshold |
| `AirflowBox.min/max.y` | World Y solid / emitter band |

### 6.2 How height is represented today

**Catalog / meshes**

- `lib/services/gltf_catalog.dart` — canonical per-icon `heightMeters`, `airflowSolid`, `lightTransmit`, role (`solid`/`emitter`/`opening`/`glass`). Examples: desk 0.74, table 0.45, chair 1.05, bed 0.55, shelf 1.8, wardrobe 1.9, lamp 0.42, floorLamp 1.55, window clearHeight 1.1, door 1.92, wall AC 0.30, fan 1.05.
- `lib/services/placement_catalog.dart` — 2D clearances + placement class; **no vertical height field**.
- `lib/services/furniture_sprites.dart` — 2D art; not sim height.
- `lib/models/surface_mount.dart` — mount bands: `windowBottom=0.95`, `windowTop=2.05`, `ventBottom=1.85`, `ventTop=2.17`, `acBottom=1.88`, `acTop=2.18`, `deskTop` from GLTF desk height.

**Airflow (3D boxes, not pure 2D)**

- `_buildBoxes` → `_itemHeight` from GLTF mesh (`airflow_simulator.dart:922–1005`, `:1254–1288`).
- Solids rasterized in **x,y,z** (`_rasterizeSolid` ~1467–1478): voxels from floor (`min.y` usually 0) up to mesh top. **Air can pass above short furniture.**
- Gaps: solids are **axis-aligned full blocks** (no legs/porosity); `airflowSolid` scales emitter strength but raster is binary once box is added; open shelves treated like closed volumes; mid-height bridge over a coffee table is OK, but a wall-AC throw at y≈2.0 still treats a 1.9 m wardrobe as a full vertical wall in plan for any overlapping band.

**Lighting (2.5D)**

- Occluders store plan AABB + scalar `height` (`lighting_simulator.dart:278–314`).
- `_solidFloorBlocker` skips if `o.height < 1.35` (~318–324) — low items do not kill floor cell light fill.
- `_rayTransmittance` is an **XZ** walk; skips if `o.height <= lightY * 0.45` (~379); not a true 3D ray vs sill/head.
- Ceiling lights at `roomHeight - 0.05`; windows as directional with light.y from mount.

**Auto-Rig / collision / scan**

- `layout_collision.dart` — pure 2D AABB; `skipsFloorOccupancy` for ceiling/wall mounts.
- Optimizers nudge in grid X/Y only; `FurnitureItem.height` means footprint depth.
- `scan_layout_converter.dart` — uses `sizeMeters.x/z` for footprint; scanned `y` mostly for openings priors, not persisted as FurnitureItem world height.

### 6.3 File:line index — places that assume planar / coarse height blocking

Treat as audit checklist for Rig App + Rig ML when implementing:

| Location | Assumption |
| --- | --- |
| `layout_collision.dart:37–48`, `:417–425` | 2D overlap = block |
| `layout_optimizer_common.dart` (throughout footprint clamps) | Plan packing only |
| `hierarchical_layout.dart` | Plan wall pins |
| `multi_objective_optimizer.dart` / Auto-Rig candidates | No vertical feasibility |
| `lighting_simulator.dart:318–324` | Binary tall/short at 1.35 m for floor fill |
| `lighting_simulator.dart:355–399` | XZ transmittance; height as gate vs `lightY*0.45` |
| `airflow_simulator.dart:989–1004` | Full rectangular prism solid (no porosity/legs) |
| `airflow_simulator.dart:1467–1478` | Binary voxel fill of AABB |
| `comfort_heuristics.dart` HVAC zone | Plan pad around vent, ignores vertical overlap with throw band |
| `autorug_ranker.dart` features | No height / porosity features |
| `scan_layout_converter.dart:218–242` | Footprint from xz; vertical not on FurnitureItem |
| Prototypes `*_prototype.dart` | Narrative "blocks throw" in plan |

**Not purely 2D (already better):** airflow box heights + voxel Y; lighting height thresholds; SurfaceMounts window/AC bands; GLTF profiles.

### 6.4 Proposed height model

**Per-type fields** (extend `MeshProfile` or parallel `HeightProfile` — Rig App schema):

| Field | Meaning |
| --- | --- |
| `heightMeters` | Top of object AFF (keep) |
| `baseClearMeters` | Leg/open base (table ~0.3–0.4 clear under top) |
| `porosity` | 0=closed wardrobe … 1=empty frame; open shelf ~0.4–0.7 |
| `mount` | `floor` / `wall` / `ceiling` / `desktop` |
| `emitterBand` | (y0,y1) for AC/fan/vent/window |

**Size classes (for UI + coarse rules):** low (<0.7 m), medium (0.7–1.35 m), tall (>1.35 m) — align lighting's 1.35 heuristic with evidence.

**Draft per-class targets** (typical ranges; replace with Neufert/Panero/BIFMA edition pins when books in hand). Mark **UNVERIFIED BOOK PAGE** where we only have secondary web summaries:

| Class | App `heightMeters` now | Typical real range | Source notes |
| --- | --- | --- | --- |
| Desk | 0.74 | ~0.71–0.76 m work surface | Common office standard; confirm Panero/BIFMA |
| Coffee / lounge table | 0.45 | ~0.40–0.46 m | Secondary dimension charts |
| Chair (overall) | 1.05 | Seat ~0.38–0.51 m (BIFMA-cited bands); back higher | Seat vs overall must be split later |
| Bed (mattress top) | 0.55 | Varies widely | Prefer dataset median |
| Sofa | 0.85 | Seat ~0.4–0.45; back ~0.8–1.0 | Secondary charts |
| Shelf / bookcase | 1.8–1.85 | Often 1.8–2.1 | Neufert modules — **confirm edition** |
| Wardrobe | 1.9 | Often ~2.0+ | Neufert — **confirm** |
| Floor lamp | 1.55 | ~1.5–1.8 | Manufacturer typical |
| Desk lamp | 0.42 | Shade height on desk | |
| Window clear | 1.1 (sill band 0.95–2.05 in SurfaceMounts) | Sill often **~0.8–1.0 m** AFF residential | Arch references; match local housing |
| Wall AC / high vent | bands ~1.85–2.2 | Indoor heads often ~1.8–2.1 m | Install guides (e.g. DOE mini-split job aid) |
| Door | 1.92 | ~2.0–2.1 clear | |

### 6.5 Evidence-backed blocking rules (proposal)

1. **Vertical cross-section test:** for a horizontal flow/light ray at height `h`, object blocks iff plan hits and `[baseClear, heightMeters]` overlaps `[h−ε, h+ε]` (or emitter beam cone).  
2. **Occupant bands (ASHRAE 55):** evaluate airflow metrics at **0.1 / 0.6 / 1.1 m** (seated) and optionally **1.7 m** standing; low tables matter at 0.1–0.6, wardrobes at all bands.  
3. **Fractional / porous block:** transmittance `1 - airflowSolid*(1-porosity)` for lighting; for airflow, density scaling instead of binary solid when porosity>0 (open bookcase).  
4. **Lighting:** replace XZ-only walk with 3D segment from light `(x,y,z)` to task point (desk top `deskTop`, seated eye ~1.2 m, standing eye ~1.7 m). Keep glass transmit.  
5. **HVAC clearance:** require clear voxels in the **throw band** (AC y∈[acBottom,acTop]), not only plan pad.  
6. **Low furniture:** stools/ottomans/coffee tables → do not mark solid above `heightMeters`; do not count as `_solidFloorBlocker`.

### 6.6 Migration, tests, ownership

**Score shift risks:** dead-zone and circulation will improve when air paths over low furniture open; lighting exposure may rise when short occluders stop shadowing ceiling sources; Benchmark pass rates will drift — **recalibrate** pass bars after flag-on golden runs, do not silently keep 50.5.

**Tests likely needing updates (Rig App):**  
`airflow_*_test.dart`, `lighting_optimizer_test.dart`, `benchmark_*_test.dart`, `autorug_ranker_test.dart`, `comfort_heuristics_test.dart`, `auto_rig_benchmark_alignment_test.dart`, honesty/credibility tests that freeze scores.

**Rollout without breaking saves:**

1. Defaults: if item lacks height, `GltfCatalog.profileForItem` (already).  
2. Schema: optional `heightMeters` override on furniture JSON; version field on layout.  
3. Feature flag: `heightAwareSims` (default off) until metrics rebaselined.  
4. Retrain ranker **after** sims change (teacher shift).  
5. No change to grid `width`/`height` meaning (avoid breaking Orbit).

**Ownership split**

| Owner | Owns |
| --- | --- |
| **Rig App** | `MeshProfile` / furniture schema, SurfaceMounts bands, sim implementation behind flag, UI explain copy, golden tests, catalog numbers |
| **Rig ML** | Evidence table, proposed numeric targets, evaluation harness in `ml/`, ranker retrain recipe, dataset mapping, this plan doc |

---

## 7. Phased roadmap

| Phase | Work | Train? | App code? |
| --- | --- | --- | --- |
| **1 (this doc)** | Inventory + evidence + height plan | No | No |
| **2** | Freeze `evidence_sources` table; annotate each constant with source_id / UNBACKED | No | Docs + maybe comments only |
| **3** | Height-aware sims behind flag; recalibrate Benchmark bars; expand tests | No | Yes (Rig App) + eval (Rig ML) |
| **4** | Preference logging + offline dataset build (non-3D-FRONT for product) | Prep only | Yes |
| **5** | New ranker on prefs + constraints; A/B vs rules | Yes | Toggle wires to new weights |
| **6** | Optional generative placer (research weights vs product weights split for license) | Yes | Yes |

### Risks

- **3D-FRONT / 3D-FUTURE license:** research-only; **no commercial product weights** trained on it. Use for papers / internal non-product experiments only; product path = user prefs + synthetic legal data + public ToU datasets.  
- **SUNCG:** unavailable — skip.  
- **False certification:** UI must not claim ADA/ASHRAE/IES compliance.  
- **Score continuity:** height flag and new pass bars will move Hub numbers; communicate in release notes.  
- **Demo grid pressure:** many clearances already shrunk to fit 6×8 @ 0.6 m/cell — evidence meters may not fit small rooms; expose "relaxed for small room" explicitly.

---

## 8. Open questions

1. Product license strategy: can Room Rig ever ship a model touched by 3D-FRONT research checkpoints, or must product training be firewalled?  
2. Should Benchmark aspire to **lux / m/s proxies** with a one-time hardware calibration, or stay unitless forever with cited *relative* bars?  
3. Minimum preference N before replacing distillation teacher?  
4. Who sets admin feature flag defaults for `heightAwareSims` (Rig App vs Bud)?  
5. Confirm Neufert / Panero **page-level** numbers with physical or legally obtained copies before UI citations (web summaries are not enough for book page claims).  
6. Ceiling-fan / stool / ottoman classes: add to catalog or map into existing icons?

---

## 9. References opened for this plan

- OSHA Computer Workstations eTools (environment / monitors)  
- U.S. Access Board ADA guides (clear floor §305; accessible routes Ch.4)  
- ASHRAE 55 measurement heights (standard text / addenda summaries)  
- EN 12464-1:2021 office illuminance tables (secondary compilations + standard excerpts)  
- 3D-FRONT Data Sets Use License Agreement (Tao Bao)  
- ATISS (NeurIPS 2021), SceneFormer (3DV 2021), DiffuScene (CVPR 2024 / arXiv:2303.14207)  
- Structured3D site; ScanNet; Hypersim license notes; SUNCG unavailability reports  
- ENERGY STAR / CBE ceiling fan height guidance; residential window sill height ranges from architecture references  

Code paths cited throughout §2–§6 are from the Room Rig tree on this machine as of 2026-10-30.

---

*End of Phase 1 plan.*
