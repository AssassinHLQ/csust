"""追踪：构建流程每一步之后，四面墙还在不在。

对每一步打印：
  · 对象数 / 三角面
  · 用「墙的指纹」找墙：尺寸 ≈ (0.21, 10.7, 3.0) 或 (8.78, 0.21, 3.0) 这类
    竖直薄板（高≈3.0、某一水平维≈0.2、另一维 >5）

用法：
  & blender -b --factory-startup --python tools\\diag_pipeline_trace.py -- <fbx> <glb目标路径>
"""

import sys
import os

import bpy
import mathutils
from mathutils import Vector, Matrix


def log(m):
    print("[trace] %s" % m)


def tri_count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def world_aabb(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


def axis_aligned_size(o):
    lo, hi = world_aabb(o)
    return hi - lo


def count_walls(meshes, tag):
    """墙：竖直薄板 —— 某个水平维厚度 < 0.35m，另一个水平维 > 3m，高度 > 2.5m。

    注意：FBX 原始是 Z 向上（Blender 里 Z=高）；
    转轴后高度会跑到 Blender 的 Z 也还是 Z（fix_axes 是把 Y 长轴转到 Y？）。
    这里不猜轴，只按「有一个维度 < 0.35、一个 > 3.0、一个在 2.5~4.0」来抓。
    """
    found = []
    for o in meshes:
        s = axis_aligned_size(o)
        dims = sorted([s.x, s.y, s.z])
        thin, mid, big = dims[0], dims[1], dims[2]
        if thin < 0.35 and mid > 2.5 and big > 3.0:
            found.append((o.name, s.x, s.y, s.z, tri_count(o)))
    log("%-14s objects=%-5d tris=%-9d WALLS=%d"
        % (tag, len(meshes), sum(tri_count(o) for o in meshes), len(found)))
    return found


def load(src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src, use_custom_normals=True)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def dedupe(meshes, eps=0.02):
    info = []
    for o in meshes:
        lo, hi = world_aabb(o)
        info.append((o, lo, hi, hi - lo, tri_count(o)))
    drop = set()
    for i in range(len(info)):
        o1, a1, b1, s1, t1 = info[i]
        if o1.name in drop:
            continue
        for j in range(i + 1, len(info)):
            o2, a2, b2, s2, t2 = info[j]
            if o2.name in drop or t1 != t2:
                continue
            if (s1 - s2).length > 0.01:
                continue
            if ((a1 + b1) * 0.5 - (a2 + b2) * 0.5).length > eps:
                continue
            loser = o2 if len(o2.name) < len(o1.name) else o1
            drop.add(loser.name)
            if loser is o1:
                break
    for name in drop:
        o = bpy.data.objects.get(name)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def fix_axes(meshes):
    def sz(ms):
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for o in ms:
            a, b = world_aabb(o)
            for i in range(3):
                lo[i] = min(lo[i], a[i])
                hi[i] = max(hi[i], b[i])
        return hi - lo

    size = sz(meshes)
    log("fix_axes 前 size=(%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))
    if size.y > size.z:
        log("  绕 X 轴 +90 度（长边在 Y）")
        rot = Matrix.Rotation(1.5707963267948966, 4, "X")
        for o in meshes:
            o.data.transform(rot @ o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        size = sz(meshes)
        log("fix_axes 后 size=(%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))
    return meshes


def decimate(meshes, target):
    total = sum(tri_count(o) for o in meshes)
    if total <= target:
        log("减面跳过")
        return meshes
    ratio = target / float(total)
    log("ratio=%.4f" % ratio)
    heavy = sum(tri_count(o) for o in meshes if tri_count(o) >= 20000)
    h_ratio = min(1.0, (target * 0.85) / float(heavy)) if (heavy > 0 and heavy > target * 0.5) else ratio
    log("h_ratio=%.4f" % h_ratio)
    for o in meshes:
        t = tri_count(o)
        if t < 400:
            continue
        r = h_ratio if t >= 20000 else max(ratio, 0.35)
        if r >= 0.999:
            continue
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        m = o.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = max(0.02, r)
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=m.name)
        o.select_set(False)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def merge_by_material(meshes):
    bpy.ops.object.select_all(action="DESELECT")
    for o in list(meshes):
        if len([s for s in o.material_slots if s.material]) > 1:
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            try:
                bpy.ops.mesh.separate(type="MATERIAL")
            except RuntimeError:
                pass
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    buckets = {}
    for o in meshes:
        m = o.material_slots[0].material if o.material_slots else None
        key = m.name if m else "<none>"
        buckets.setdefault(key, []).append(o)
    out = []
    for key, group in buckets.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = "M_" + key[:40]
        joined.select_set(False)
        out.append(joined)
    return out


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    src = args[0]

    meshes = load(src)
    count_walls(meshes, "0 import")

    meshes = dedupe(meshes)
    count_walls(meshes, "1 dedupe")

    meshes = fix_axes(meshes)
    count_walls(meshes, "2 fix_axes")

    meshes = decimate(meshes, 450000)
    count_walls(meshes, "3 decimate")

    meshes = merge_by_material(meshes)
    count_walls(meshes, "4 merge")

    log("---- 最终每个网格 ----")
    for o in sorted(meshes, key=lambda x: -tri_count(x)):
        s = axis_aligned_size(o)
        log("  %-44s tris=%-7d size=(%.3f, %.3f, %.3f)" % (o.name, tri_count(o), s.x, s.y, s.z))


main()
