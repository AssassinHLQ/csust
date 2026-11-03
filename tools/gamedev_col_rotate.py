"""把「斜放的家具套了一个轴对齐盒子」的碰撞盒，换成**绕 Y 旋转**的紧致盒子。

做法：对每个家具盒，取落在盒内的模型顶点，在 XZ 平面上暴力扫角度（0~90°，0.5° 步进），
找「包围矩形面积最小」的那个角度；再把盒子按这个角度转过去。

只改**改善 ≥ 阈值**的盒子（默认 10%），别的原样不动 —— 用户要的是「细化一点点」。

    python tools/gamedev_col_rotate.py            # 只报告
    python tools/gamedev_col_rotate.py --apply    # 真改 scenes/gamedev_room.tscn
"""
from __future__ import annotations

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gamedev_col_fit import parse_tscn, mesh_vertices, TSCN  # noqa: E402

# 墙体 / 地板 / 天花板 / 门框不参与（它们本来就该是轴对齐的）
SKIP = ("Wall", "Floor", "Ceiling", "Door")
THRESHOLD = 0.10          # 至少省 10% 才动
MIN_VERTS = 40


def fit_rect(pts: list[tuple[float, float, float]], cx: float, cz: float):
    """返回 (best_angle, w, d, cx2, cz2)。角度单位弧度。"""
    best = (0.0, 1e9, 1e9, cx, cz)
    best_area = 1e18
    steps = 180                       # 0~90°，0.5°
    for i in range(steps):
        a = math.radians(i * 0.5)
        ca, sa = math.cos(a), math.sin(a)
        mnx = mnz = 1e18
        mxx = mxz = -1e18
        for p in pts:
            u = p[0] * ca - p[2] * sa
            v = p[0] * sa + p[2] * ca
            if u < mnx:
                mnx = u
            if u > mxx:
                mxx = u
            if v < mnz:
                mnz = v
            if v > mxz:
                mxz = v
        w = mxx - mnx
        d = mxz - mnz
        area = w * d
        if area < best_area:
            best_area = area
            # 矩形中心（转到世界）
            cu = (mnx + mxx) * 0.5
            cv = (mnz + mxz) * 0.5
            wx = cu * ca + cv * sa
            wz = -cu * sa + cv * ca
            best = (a, w, d, wx, wz)
    return best


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    apply = "--apply" in sys.argv
    _, boxes = parse_tscn()
    verts = mesh_vertices()

    changes = []
    print(f"{'盒名':<20}{'原尺寸':>22}{'新尺寸':>22}{'省':>7}{'转角':>8}")
    print("-" * 82)
    for b in boxes:
        if any(k in b["name"] for k in SKIP):
            continue
        sx, sy, sz = b["size"]
        half = [sx / 2, sy / 2, sz / 2]
        ox, oy, oz = b["origin"]
        pts = [v for v in verts
               if abs(v[0] - ox) <= half[0] and abs(v[1] - oy) <= half[1]
               and abs(v[2] - oz) <= half[2]]
        if len(pts) < MIN_VERTS:
            continue
        ang, w, d, cx, cz = fit_rect(pts, ox, oz)
        # ⚠️ **高度保持原样**。用顶点 Y 范围收紧会把 `Col_chair_01` 从 0.50 压到 0.22，
        #    玩家就能跨过椅背了 —— 用户要的是「斜放的家具别套正方盒子」，不是「变矮」。
        h = sy
        cy = oy
        old_vol = sx * sy * sz
        new_vol = w * h * d
        gain = 1.0 - new_vol / old_vol
        if gain < THRESHOLD:
            continue
        change = {
            "name": b["name"], "shape": b["shape"],
            "size": (w, h, d), "angle": ang, "center": (cx, cy, cz),
            "old": (sx, sy, sz), "gain": gain,
        }
        changes.append(change)
        print(f"{b['name']:<20}{sx:>7.2f}×{sy:>5.2f}×{sz:>6.2f}"
              f"{w:>8.2f}×{h:>5.2f}×{d:>6.2f}{gain*100:>6.0f}%{math.degrees(ang):>7.1f}°")

    if not changes:
        print("\n没有需要旋转的盒子。")
        return 0
    print(f"\n共 {len(changes)} 个盒子可收紧。")

    if not apply:
        print("（只是报告。加 --apply 才会改写 scenes/gamedev_room.tscn）")
        return 0

    text = open(TSCN, encoding="utf-8").read()
    for c in changes:
        w, h, d = c["size"]
        # 1) 改 size
        pat_sz = re.compile(
            r'(\[sub_resource type="BoxShape3D" id="%s"\]\s*\n)size = Vector3\([^)]*\)'
            % re.escape(c["shape"]))
        text, n1 = pat_sz.subn(lambda m: m.group(1) + f"size = Vector3({w:.6f}, {h:.6f}, {d:.6f})", text)
        # 2) 改 transform：绕 Y 的旋转基 + 新中心
        a = c["angle"]
        ca, sa = math.cos(a), math.sin(a)
        # Godot 的 Y 旋转：基为 [[cos,0,sin],[0,1,0],[-sin,0,cos]]（行优先写 Transform3D）
        basis = (ca, 0.0, sa, 0.0, 1.0, 0.0, -sa, 0.0, ca)
        cx, cy, cz = c["center"]
        tr = (f"transform = Transform3D({basis[0]:.6f}, {basis[1]:.6f}, {basis[2]:.6f}, "
              f"{basis[3]:.6f}, {basis[4]:.6f}, {basis[5]:.6f}, "
              f"{basis[6]:.6f}, {basis[7]:.6f}, {basis[8]:.6f}, "
              f"{cx:.6f}, {cy:.6f}, {cz:.6f})")
        pat_tf = re.compile(
            r'(\[node name="%s" type="CollisionShape3D" parent="[^"]+"\]\s*\n)transform = Transform3D\([^)]*\)'
            % re.escape(c["name"]))
        text, n2 = pat_tf.subn(lambda m: m.group(1) + tr, text)
        if n1 != 1 or n2 != 1:
            print(f"  !! {c['name']} 改写失败（size {n1} 处 / transform {n2} 处）")
            return 2

    open(TSCN, "w", encoding="utf-8", newline="\n").write(text)
    print(f"已写入 {TSCN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
