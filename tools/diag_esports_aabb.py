"""诊断：找出「AABB 盒子比物体本身大很多」的件（碰撞偏大/偏移的元凶）。

用法：
    blender --background --factory-startup --python tools/diag_esports_aabb.py -- \
        --in "C:\\Users\\WY157\\Desktop\\游戏开发电竞房.fbx"

做法：对每件物体算两个量
  · AABB 体积（现在的做法就是一个盒子 = 这个体积）
  · 实际占据的**体素格数**（把 AABB 切成 ~0.25 m 的格子，看有多少格**真的**有三角面）
  两者比值 = 「填充率」。填充率低 = 盒子把空气也算成碰撞了 → 玩家撞到看不见的墙。

2026-11-09 使用者：「这一面墙的碰撞偏了很多」——就是这个毛病。
"""
import argparse
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector


def log(*a):
    print("[diag]", *a, flush=True)


def tri_count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def world_aabb(o):
    corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
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
    ap = argparse.ArgumentParser(prog="diag_esports_aabb")
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--cell", type=float, default=0.25, help="体素边长（米）")
    ap.add_argument("--top", type=int, default=25, help="打印最差的几件")
    return ap.parse_args(argv)


def vertices_world(o):
    """物体所有顶点 → 世界坐标（numpy 向量化，快）"""
    me = o.data
    n = len(me.vertices)
    if n == 0:
        return None
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    M = np.array(o.matrix_world, dtype=np.float64)
    return co @ M[:3, :3].T + M[:3, 3]


def occupied_cells(o, cell, max_cells=200000):
    """把物体顶点落进格子，返回去重后的格子数。

    ⚠️ 只用**顶点**是近似：低面数的平板（墙只有十几个顶点）会低估。
    所以对顶点少的物体，改成**三角形 AABB** 覆盖（见调用处）。
    """
    w = vertices_world(o)
    if w is None:
        return 0
    c = np.floor(w / cell).astype(np.int64)
    # 用唯一化去重：把三列拼成结构化 key
    uniq = np.unique(c, axis=0)
    return int(uniq.shape[0])


def occupied_cells_by_tri(o, cell):
    """按**三角形 AABB** 覆盖格子（对低面数物体更准）。

    ⚠️ 三角形多时会慢，所以调用处只在 tri_count 小的时候走这条。
    """
    me = o.data
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    if nt == 0:
        return 0
    w = vertices_world(o)
    if w is None:
        return 0
    tris = np.empty(nt * 3, dtype=np.int32)
    me.loop_triangles.foreach_get("vertices", tris)
    tris = tris.reshape(nt, 3)
    cells = set()
    for t in range(nt):
        idx = tris[t]
        pts = w[idx]
        lo = np.floor(pts.min(axis=0) / cell).astype(np.int64)
        hi = np.floor(pts.max(axis=0) / cell).astype(np.int64)
        for x in range(lo[0], hi[0] + 1):
            for y in range(lo[1], hi[1] + 1):
                for z in range(lo[2], hi[2] + 1):
                    cells.add((x, y, z))
    return len(cells)


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    log("载入 %s" % os.path.basename(a.src))
    bpy.ops.import_scene.fbx(filepath=a.src, use_custom_normals=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    log("对象 %d / 三角面 %d" % (len(meshes), sum(tri_count(o) for o in meshes)))

    # 这些是 build/dump 脚本会做的：去重（这里只做单用户化 + 摆正）
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
    size = aabb_size(meshes)
    if size.y > size.z:
        rot = Matrix.Rotation(1.5707963267948966, 4, "X")
        for o in meshes:
            o.data.transform(rot @ o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        x, y = world_aabb(o)
        for i in range(3):
            lo[i] = min(lo[i], x[i])
            hi[i] = max(hi[i], y[i])
    shift = Vector((-(lo.x + hi.x) * 0.5, -lo.y, -(lo.z + hi.z) * 0.5))
    for o in meshes:
        o.data.transform(Matrix.Translation(shift) @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    rows = []
    for o in meshes:
        t = tri_count(o)
        if t == 0:
            continue
        a1, b1 = world_aabb(o)
        sz = b1 - a1
        vol = sz.x * sz.y * sz.z
        if vol < 0.001:
            continue
        if t <= 400:
            ncell = occupied_cells_by_tri(o, a.cell)
        else:
            ncell = occupied_cells(o, a.cell)
        filled = ncell * (a.cell ** 3)
        ratio = filled / vol if vol > 0 else 0.0
        rows.append((ratio, vol, filled, ncell, t, o.name, sz))

    rows.sort(key=lambda r: r[0])
    log("── 填充率最低的 %d 件（盒子把空气也算成碰撞）──" % a.top)
    log("%-24s %6s %8s %8s %7s %6s  %s" % (
        "名字", "面数", "AABB体积", "占用体积", "填充率", "格数", "尺寸"))
    for r in rows[:a.top]:
        log("%-24s %6d %8.2f %8.2f %6.1f%% %6d  %.2f×%.2f×%.2f" % (
            r[5], r[4], r[1], r[2], r[0] * 100.0, r[3], r[6].x, r[6].y, r[6].z))

    bad = [r for r in rows if r[0] < 0.5 and r[1] > 0.05]
    log("── 汇总 ──")
    log("总件数 %d；填充率 <50%% 且 AABB 体积 >0.05 m³ 的「偏大」件：**%d 个**"
        % (len(rows), len(bad)))
    log("这些件如果各给一个 AABB 盒，就多算了 %.1f m³ 的空气碰撞"
        % sum(r[1] - r[2] for r in bad))


main()
