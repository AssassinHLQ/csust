#!/usr/bin/env python3
"""Scan GLB/GLTF files and count triangles by parsing glTF accessors directly.

Does not use Godot, does not touch .godot/, does not re-import.
Counts only primitives with mode == 4 (TRIANGLES); other modes are reported
separately so points/lines are never silently folded into a triangle total.
"""
from __future__ import annotations

import json
import os
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
MODE_NAMES = {
    0: "POINTS", 1: "LINES", 2: "LINE_LOOP", 3: "LINE_STRIP",
    4: "TRIANGLES", 5: "TRIANGLE_STRIP", 6: "TRIANGLE_FAN",
}


def load_gltf_json(path: str):
    """Return (gltf_dict, has_bin) for a .glb or .gltf file."""
    with open(path, "rb") as fh:
        head = fh.read(12)
        if len(head) < 12:
            raise ValueError("file too short")
        magic, version, total = struct.unpack("<III", head)
        if magic != GLB_MAGIC:
            # Plain .gltf JSON
            fh.seek(0)
            return json.loads(fh.read().decode("utf-8-sig")), False
        clen, ctype = struct.unpack("<II", fh.read(8))
        if ctype != CHUNK_JSON:
            raise ValueError("first chunk is not JSON")
        gltf = json.loads(fh.read(clen).decode("utf-8-sig"))
        return gltf, True


def accessor_count(gltf: dict, idx: int) -> int:
    acc = gltf.get("accessors", [])[idx]
    return int(acc.get("count", 0))


def count_primitives(gltf: dict):
    """Return (tris, other_mode_counts, prim_total, mesh_count)."""
    tris = 0
    others: dict[str, int] = {}
    prim_total = 0
    meshes = gltf.get("meshes", [])
    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            prim_total += 1
            mode = int(prim.get("mode", 4))
            attrs = prim.get("attributes", {})
            if mode == 4:
                if "indices" in prim:
                    tris += accessor_count(gltf, prim["indices"]) // 3
                elif "POSITION" in attrs:
                    tris += accessor_count(gltf, attrs["POSITION"]) // 3
            else:
                n = 0
                if "indices" in prim:
                    n = accessor_count(gltf, prim["indices"])
                elif "POSITION" in attrs:
                    n = accessor_count(gltf, attrs["POSITION"])
                name = MODE_NAMES.get(mode, f"MODE{mode}")
                others[name] = others.get(name, 0) + n
    return tris, others, prim_total, len(meshes)


def main(argv):
    roots = argv[1:] or ["."]
    rows = []
    failures = []
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            rel_dir = os.path.relpath(dirpath, root)
            # skip import caches, tools, and the external asset library
            if any(part in rel_dir.split(os.sep) for part in (".godot", "_tools", "素材库", "可用素材", ".git")):
                continue
            for fn in filenames:
                if not fn.lower().endswith((".glb", ".gltf")):
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    gltf, _ = load_gltf_json(path)
                    tris, others, prims, meshes = count_primitives(gltf)
                except Exception as exc:  # noqa: BLE001
                    failures.append((path, str(exc)))
                    continue
                nodes = len(gltf.get("nodes", []))
                mats = len(gltf.get("materials", []))
                texs = len(gltf.get("images", []))
                rows.append({
                    "path": os.path.relpath(path, root).replace(os.sep, "/"),
                    "bytes": os.path.getsize(path),
                    "tris": tris,
                    "others": others,
                    "prims": prims,
                    "meshes": meshes,
                    "nodes": nodes,
                    "materials": mats,
                    "images": texs,
                })

    rows.sort(key=lambda r: r["tris"], reverse=True)
    total = sum(r["tris"] for r in rows)
    print(f"# glTF triangle survey — {len(rows)} files, {total:,} triangles total")
    print()
    header = f"{'#':>3}  {'triangles':>12}  {'MB':>8}  {'mesh':>4} {'prim':>5} {'mat':>4} {'tex':>4}  path"
    print(header)
    print("-" * len(header))
    for i, r in enumerate(rows, 1):
        print(f"{i:>3}  {r['tris']:>12,}  {r['bytes']/1048576:>8.2f}  "
              f"{r['meshes']:>4} {r['prims']:>5} {r['materials']:>4} {r['images']:>4}  {r['path']}")
        if r["others"]:
            print(f"     non-triangle primitives: {r['others']}")
    if failures:
        print()
        print("# FAILED")
        for path, err in failures:
            print(f"  {path}: {err}")

    # machine-readable sidecar so later tooling does not reparse
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tri_rank.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"total_tris": total, "rows": rows}, fh, ensure_ascii=False, indent=2)
    print()
    print(f"# json sidecar: {out}")


if __name__ == "__main__":
    main(sys.argv)
