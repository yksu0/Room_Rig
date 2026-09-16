#!/usr/bin/env python3
"""Canonical Room Rig detector class list + remaps from public datasets."""

from __future__ import annotations

# Order MUST match assets/models/yolo_roomrig_target_labels.txt and the trained head.
ROOMRIG_CLASSES: list[str] = [
    "door",
    "window",
    "desk",
    "chair",
    "bed",
    "sofa",
    "tv",
    "monitor",
    "pc",
    "lamp",
    "fan",
    "ac",
    "shelf",
    "wardrobe",
    "plant",
    "purifier",
    "vent",
    "blinds",
]

# HomeObjects-3K class index → Room Rig class name (drop photo frame).
HOMEOBJECTS_TO_ROOMRIG: dict[str, str | None] = {
    "bed": "bed",
    "sofa": "sofa",
    "chair": "chair",
    "table": "desk",  # closest public stand-in for work/lounge tables
    "lamp": "lamp",
    "tv": "tv",
    "laptop": "pc",
    "wardrobe": "wardrobe",
    "window": "window",
    "door": "door",
    "potted plant": "plant",
    "photo frame": None,
}

# COCO-80 names → Room Rig (used when mining additional COCO images).
COCO_TO_ROOMRIG: dict[str, str | None] = {
    "chair": "chair",
    "couch": "sofa",
    "bed": "bed",
    "dining table": "desk",
    "tv": "tv",
    "laptop": "pc",
    "keyboard": "pc",
    "mouse": "pc",
    "potted plant": "plant",
    "book": "shelf",
}

# Roboflow extras under ml/datasets/extra/<name>/ — source class → Room Rig.
# Unlisted source names are dropped.
EXTRA_DATASET_MAPS: dict[str, dict[str, str]] = {
    "monitor": {
        "Monitor": "monitor",
    },
    "inside": {
        "air-conditioner": "ac",
        "ceiling-fan": "fan",
        "shelf": "shelf",
        "shelves": "shelf",
        "curtains": "blinds",
        "bed": "bed",
        "chair": "chair",
        "door": "door",
        "window": "window",
        "windows": "window",
        "sofa": "sofa",
        "television": "tv",
        "lamps": "lamp",
        "table-lamp": "lamp",
        "plant": "plant",
        "plants": "plant",
        "indoor-plant": "plant",
        "table": "desk",
        "tables": "desk",
        "center-table": "desk",
        "side-table": "desk",
        "cupboard": "wardrobe",
        "book": "shelf",
    },
    "shelf": {
        "book": "shelf",
    },
    "blinds": {
        "curtain": "blinds",
        "bed": "bed",
        "chair": "chair",
        "door": "door",
        "lamp": "lamp",
        "plant": "plant",
        "tvmonitor": "tv",
        "window": "window",
    },
    "purifier": {
        "air purifier": "purifier",
    },
    "vent": {
        "Air-Vent-Hole": "vent",
        "Air Inlet": "vent",
        "Air Outlet": "vent",
        "air_inlet": "vent",
        "air_outlet": "vent",
        "vent": "vent",
        "AIR GRILL": "vent",
        "damper": "vent",
        "heater": "vent",
        "Heater": "vent",
        "radiator": "vent",
    },
    "fan": {
        "fan": "fan",
        "Fan": "fan",
        "ceiling-fan": "fan",
        "ceiling_fan": "fan",
        "Ceiling Fan": "fan",
    },
    "ac": {
        "air_conditioning": "ac",
        "air-conditioner": "ac",
        "AC": "ac",
        "ac": "ac",
        "Climatiseur Type 1": "ac",
        "climatiseur": "ac",
    },
    "blinds2": {
        "curtain": "blinds",
        "Curtain": "blinds",
    },
    "renovia": {
        "Climatiseur Type 1": "ac",
        "Bouche d-aeration": "vent",
        "Radiateur Type 1": "vent",
        "Radiateur Type 2": "vent",
    },
}

CLASS_TO_ID = {name: i for i, name in enumerate(ROOMRIG_CLASSES)}
