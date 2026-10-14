"""Download a Poly Haven 1k glTF model pack into assets/gltf/hvac/<id>/."""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def download(asset_id: str, out_name: str | None = None) -> Path:
    name = out_name or asset_id
    dest = ROOT / "assets" / "gltf" / "hvac" / name
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "textures").mkdir(exist_ok=True)

    ua = (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    )
    opener = urllib.request.build_opener()
    opener.addheaders = [("User-Agent", ua)]
    urllib.request.install_opener(opener)

    api = f"https://api.polyhaven.com/files/{asset_id}"
    with urllib.request.urlopen(api) as r:
        data = json.load(r)
    pack = data["gltf"]["1k"]["gltf"]
    gltf_url = pack["url"]
    gltf_path = dest / f"{name}.gltf"
    print("GET", gltf_url)
    urllib.request.urlretrieve(gltf_url, gltf_path)

    for rel, meta in pack["include"].items():
        path = dest / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        print("GET", rel, meta.get("size"))
        urllib.request.urlretrieve(meta["url"], path)

    # Rewrite .gltf name reference if needed — keep as-is; loader uses folder.
    print("OK", dest)
    return dest


if __name__ == "__main__":
    ids = sys.argv[1:] or [
        "exterior_aircon_unit",
        "modular_airduct_rectangular_01",
    ]
    for asset_id in ids:
        download(asset_id)
