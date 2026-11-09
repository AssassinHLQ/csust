"""从未合并的 FBX 里**逐件**量世界包围盒，输出 JSON 给 Godot 烘碰撞用。

用法：
    blender --background --factory-startup --python tools/dump_esports_parts.py -- \
        --in "C:\\Users\\WY157\\Desktop\\游戏开发电竞房.fbx" \
        --out models/esports_room/esports_parts.json

── 为什么要有这个脚本（2026-11-09）──
使用者：「你总是做大了碰撞，书本桌子本来是两个不同的碰撞，结果你只做一个大的碰撞。」

根因：`build_esports_room.py` 的 `merge_by_material()` 把 **738 个独立物件**
按材质合并成 **59 个材质桶**（为了省 draw call）。于是「书」和「桌子」如果同材质，
就进了同一个网格 —— 只能给整个网格一个包围盒，碰撞就变成一大坨。

这个脚本**不做合并**，直接输出每件物体自己的 AABB。
Godot 侧再用 `scripts/_bake_esports_parts.gd` 把这份 JSON 烘成
「一件一个 BoxShape3D」的碰撞场景。

⚠️ 坐标处理必须和 `build_esports_room.py` **完全一致**，否则碰撞对不上：
   1. `dedupe`    —— 去掉重复件（同尺寸/同面数/中心很近）
   2. `fix_axes`  —— 长边在 Y 时绕 X 转 +90°（房间比例 高3.6 : 宽10.4 : 深16.84）
   3. `center_and_floor` —— XZ 居中、底面落到 y=0
   Blender 坐标 **原样** 写进 glTF（导出时 `export_yup=False`），
   而 Godot 读到的是 (x, y, z) 直接对应 —— 所以这里的 AABB 就是 Godot 局部坐标。
"""
import argparse
import json
import os
import sys

import bpy
from mathutils import Matrix, Vector


def log(*a):
    print("[parts]", *a, flush=True)


def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def world_aabb(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


def aabb_size(meshes):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        a, b = world_aabb(o)
        for i in range(3):
            lo[i] = min(lo[i], a[i])
            hi[i] = max(hi[i], b[i])
    return hi - lo


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    ap = argparse.ArgumentParser(prog="dump_esports_parts")
    ap.add_argument("--in", dest="src", required=True, help="原始 FBX")
    ap.add_argument("--out", dest="dst", required=True, help="输出 JSON")
    ap.add_argument("--dedupe-eps", type=float, default=0.02, help="判重中心差（米）")
    ap.add_argument("--min-tris", type=int, default=4, help="小于这个面数不输出（碎片）")
    return ap.parse_args(argv)


def make_single_user(meshes):
    """把**共用网格数据**的对象拆成各自独立的一份。

    ⚠️ 2026-11-09 踩的坑：FBX 导入时多个对象会**共用同一份 mesh datablock**。
    本脚本后面用 `o.data.transform(...)` 直接改网格数据来摆正 / 居中，
    共用数据会被**反复变换 N 次**，于是同一个物体被堆叠成好几份 ——
    实测整体高度从 3.60 m 虚增到 **6.53 m**（9 件物体按 1.1 m 等差异位，
    例如 JS2929 y5.62~6.53 / JS2786 y4.52~5.43 / JS2643 y3.42~4.33）。
    """
    n = 0
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
            n += 1
    log("单用户化：%d 个对象复制了网格数据（原来是共用的）" % n)


def dedupe(meshes, eps):
    """同尺寸 + 同面数 + 中心很近 = 重复，留名字短的那份。

    ⚠️ `mathutils.Vector` 是**可变**的，不能当字典键（会报
    "Vector is not frozen (mutable), call freeze first"），所以这里存元组。
    """
    seen = []
    removed = 0
    keep = []
    for o in sorted(meshes, key=lambda x: len(x.name)):
        a, b = world_aabb(o)
        size = b - a
        center = (a + b) * 0.5
        t = tri_count(o)
        dup = False
        for ks, kc, kt in seen:
            if (kt == t
                    and abs(ks[0] - size.x) < eps and abs(ks[1] - size.y) < eps
                    and abs(ks[2] - size.z) < eps
                    and abs(kc[0] - center.x) < eps and abs(kc[1] - center.y) < eps
                    and abs(kc[2] - center.z) < eps):
                dup = True
                break
        if dup:
            removed += 1
            continue
        seen.append(((size.x, size.y, size.z), (center.x, center.y, center.z), t))
        keep.append(o)
    log("去重：删 %d 个对象" % removed)
    return keep


def fix_axes(meshes):
    """和 build_esports_room.py **完全一致**的摆正逻辑。"""
    size = aabb_size(meshes)
    log("导入后包围盒 size=(%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))
    if size.y > size.z:
        log("长边在 Y、矮边在 Z → 绕 X 转 +90°")
        rot = Matrix.Rotation(1.5707963267948966, 4, "X")
        for o in meshes:
            o.data.transform(rot @ o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        size = aabb_size(meshes)
        log("转完 size=(%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))
    else:
        log("长边不在 Y → 不转")


def center_and_floor(meshes):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        a, b = world_aabb(o)
        for i in range(3):
            lo[i] = min(lo[i], a[i])
            hi[i] = max(hi[i], b[i])
    shift = Vector((-(lo.x + hi.x) * 0.5, -lo.y, -(lo.z + hi.z) * 0.5))
    for o in meshes:
        o.data.transform(Matrix.Translation(shift) @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    log("居中落底：移位 (%.3f, %.3f, %.3f)" % (shift.x, shift.y, shift.z))


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    log("载入 %s（%.1f MB）" % (a.src, os.path.getsize(a.src) / 1e6))
    bpy.ops.import_scene.fbx(filepath=a.src, use_custom_normals=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    log("对象 %d / 三角面 %d" % (len(meshes), sum(tri_count(o) for o in meshes)))

    meshes = dedupe(meshes, a.dedupe_eps)
    # ⚠️ 必须在任何 `o.data.transform()` 之前单用户化，否则共用数据会被变换多次
    make_single_user(meshes)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    fix_axes(meshes)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    center_and_floor(meshes)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    # 逐件量 AABB。名字用能读懂的（材质名 + 原名）
    parts = []
    for o in meshes:
        t = tri_count(o)
        if t < a.min_tris:
            continue
        lo, hi = world_aabb(o)
        mat = ""
        if o.material_slots and o.material_slots[0].material:
            mat = o.material_slots[0].material.name
        parts.append({
            "name": o.name,
            "mat": mat,
            "tris": t,
            "min": [round(lo.x, 5), round(lo.y, 5), round(lo.z, 5)],
            "max": [round(hi.x, 5), round(hi.y, 5), round(hi.z, 5)],
        })

    os.makedirs(os.path.dirname(os.path.abspath(a.dst)), exist_ok=True)
    with open(a.dst, "w", encoding="utf-8") as f:
        json.dump({
            "source": os.path.basename(a.src),
            "count": len(parts),
            "parts": parts,
        }, f, ensure_ascii=False, indent=1)
    log("写出 %s：%d 件物体" % (a.dst, len(parts)))

    # 收尾报告：整间房的包围盒（和 GLB 对一下）
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for p in parts:
        for i in range(3):
            lo[i] = min(lo[i], p["min"][i])
            hi[i] = max(hi[i], p["max"][i])
    log("整体包围盒 min=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % (
        lo.x, lo.y, lo.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))


main()
