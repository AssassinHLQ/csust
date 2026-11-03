"""量「盒碰撞」有多粗：每个盒子实际包住了多少模型几何，多少是空气。

思路：把 GLB 的**顶点**投到场景同一套坐标里，对每个碰撞盒统计
  · 落进盒内的顶点数
  · 这些顶点的**紧包围盒**（真正该占的空间）
  · 盒体积 / 紧包围盒体积 → 空置比例

空置比例高的盒子就是「撞到空气」的那种，优先拆细或收紧。

    python tools/gamedev_col_fit.py
"""
from __future__ import annotations

import re
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_curve import load_glb, read_accessor  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSCN = os.path.join(ROOT, "scenes", "gamedev_room.tscn")
GLB = os.path.join(ROOT, "models", "gamedev_room", "gamedev_room.glb")

RE_BOX = re.compile(r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\s*\nsize = Vector3\(([^)]+)\)')
RE_NODE = re.compile(r'\[node name="([^"]+)" type="CollisionShape3D" parent="([^"]+)"\]\s*\n'
                     r'transform = Transform3D\(([^)]+)\)\s*\nshape = SubResource\("([^"]+)"\)')


def parse_tscn() -> tuple[dict[str, tuple[float, float, float]], list[dict]]:
    text = open(TSCN, encoding="utf-8").read()
    shapes: dict[str, tuple[float, float, float]] = {}
    for sid, nums in RE_BOX.findall(text):
        v = [float(x) for x in nums.split(",")]
        shapes[sid] = (v[0], v[1], v[2])
    boxes = []
    for name, parent, tr, sid in RE_NODE.findall(text):
        if sid not in shapes:
            continue
        t = [float(x) for x in tr.split(",")]
        # Transform3D 是行优先：basis 3x3 + origin
        origin = (t[9], t[10], t[11])
        basis = ((t[0], t[1], t[2]), (t[3], t[4], t[5]), (t[6], t[7], t[8]))
        boxes.append({"name": name, "shape": sid, "size": shapes[sid],
                      "origin": origin, "basis": basis})
    return shapes, boxes


def mesh_vertices() -> list[tuple[float, float, float]]:
    g, blob = load_glb(GLB)
    out: list[tuple[float, float, float]] = []
    for mesh in g.get("meshes", []):
        for prim in mesh.get("primitives", []):
            ai = prim.get("attributes", {}).get("POSITION")
            if ai is None:
                continue
            for v in read_accessor(g, blob, ai):
                out.append((v[0], v[1], v[2]))
    return out


def world(p, box) -> tuple[float, float, float]:
    """局部点 → 盒子所在空间（只用到旋转，盒子的 basis 基本是单位/一转）。"""
    b = box["basis"]
    o = box["origin"]
    return (b[0][0] * p[0] + b[0][1] * p[1] + b[0][2] * p[2] + o[0],
            b[1][0] * p[0] + b[1][1] * p[1] + b[1][2] * p[2] + o[1],
            b[2][0] * p[0] + b[2][1] * p[1] + b[2][2] * p[2] + o[2])


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    _, boxes = parse_tscn()
    verts = mesh_vertices()
    print(f"碰撞盒 {len(boxes)} 个，模型顶点 {len(verts)} 个\n")
    print(f"{'盒名':<22}{'当前尺寸':>26}{'包住顶点':>9}{'空置比例':>9}")
    print("-" * 70)

    rows = []
    for b in boxes:
        sx, sy, sz = b["size"]
        half = [sx * 0.5, sy * 0.5, sz * 0.5]
        ox, oy, oz = b["origin"]
        n = 0
        mn = [1e9, 1e9, 1e9]
        mx = [-1e9, -1e9, -1e9]
        for v in verts:
            if abs(v[0] - ox) <= half[0] and abs(v[1] - oy) <= half[1] and abs(v[2] - oz) <= half[2]:
                n += 1
                for k in range(3):
                    mn[k] = min(mn[k], v[k])
                    mx[k] = max(mx[k], v[k])
        if n == 0:
            rows.append((1.0, b["name"], (sx, sy, sz), 0, 1.0))
            continue
        tight = [max(mx[k] - mn[k], 1e-4) for k in range(3)]
        box_vol = sx * sy * sz
        tight_vol = tight[0] * tight[1] * tight[2]
        empty = 1.0 - min(tight_vol / box_vol, 1.0)
        rows.append((empty, b["name"], (sx, sy, sz), n, empty))

    rows.sort(reverse=True)
    for empty, name, size, n, _e in rows:
        print(f"{name:<22}{size[0]:>8.2f}×{size[1]:>6.2f}×{size[2]:>7.2f}"
              f"{n:>9}{empty * 100:>8.0f}%")

    print("\n「空置比例」= 1 − 盒内顶点紧包围盒体积 / 盒体积。")
    print("  接近 0%  = 盒子基本贴着几何，没问题")
    print("  高       = 盒子大部分是空气，玩家会撞到看不见的地方")
    return 0


if __name__ == "__main__":
    sys.exit(main())
