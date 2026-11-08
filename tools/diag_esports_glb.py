"""诊断：把已经导出的 GLB 读回来，逐个网格量尺寸，判断有没有「漏转」。

对每个网格算它最长的轴：
  · 房间外壳（10 × 3.6 × 16.8）应该 X 长、Y 短、Z 最长
  · 墙应该 Y = 3.6 左右（高度）
  · 如果某个网格的「高度」落在错的轴上，就是漏转了

同时统计：有多少网格是「薄片贴在地面上」而不是「立起来的墙」。

用法：
  & blender -b --python tools\\diag_esports_glb.py -- <glb路径>
"""

import sys
import os

import bpy
import mathutils


def log(msg):
    print("[glbdiag] %s" % msg)


def measure(o):
    mw = o.matrix_world
    pts = [mw @ mathutils.Vector(c) for c in o.bound_box]
    mn = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx, (mx - mn)


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    src = args[0] if args else "models/esports_room/esports_room.glb"
    if not os.path.exists(src):
        log("找不到 %s" % src)
        return

    bpy.ops.wm.read_factory_settings(use_empty=True)
    log("导入 %s（%.1f MB）" % (src, os.path.getsize(src) / 1e6))
    bpy.ops.import_scene.gltf(filepath=src)
    bpy.context.view_layer.update()

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    log("网格数 = %d" % len(meshes))

    gmn = gmx = None
    rows = []
    for o in meshes:
        mn, mx, sz = measure(o)
        if gmn is None:
            gmn, gmx = mn.copy(), mx.copy()
        else:
            for i in range(3):
                gmn[i] = min(gmn[i], mn[i])
                gmx[i] = max(gmx[i], mx[i])
        o.data.calc_loop_triangles()
        rows.append((o.name, sz, len(o.data.loop_triangles)))

    log("全局 SIZE = (%.3f, %.3f, %.3f)" % (gmx.x - gmn.x, gmx.y - gmn.y, gmx.z - gmn.z))
    log("全局 min = (%.3f, %.3f, %.3f)  max = (%.3f, %.3f, %.3f)" % (gmn.x, gmn.y, gmn.z, gmx.x, gmx.y, gmx.z))

    # 关键：房间高度是 3.6。找「立面墙」：应该 X 或 Z 长、Y 高
    # 若某个网格 Y 尺寸 ≈ 16.8（房间长度跑到高度上），就是漏转
    log("======== 嫌疑：Y 尺寸 > 6 m 的网格（墙不该这么高） ========")
    bad = 0
    for name, sz, tris in rows:
        if sz.y > 6.0:
            bad += 1
            log("  %-46s Y=%.3f  size=(%.3f, %.3f, %.3f) tris=%d" % (name, sz.y, sz.x, sz.y, sz.z, tris))
    log("合计 %d 个" % bad)

    log("======== 正常墙面（Y 在 2.4~3.7 之间、非薄片） ========")
    walls = [r for r in rows if 2.4 <= r[1].y <= 3.7 and min(r[1].x, r[1].z) > 1.0]
    log("数量 = %d" % len(walls))
    for name, sz, tris in walls[:12]:
        log("  %-46s size=(%.3f, %.3f, %.3f) tris=%d" % (name, sz.x, sz.y, sz.z, tris))

    log("======== 面数最多的 15 件 ========")
    rows.sort(key=lambda r: -r[2])
    for name, sz, tris in rows[:15]:
        log("  %-46s tris=%-7d size=(%.3f, %.3f, %.3f)" % (name, tris, sz.x, sz.y, sz.z))

    log("======== 最扁的 12 件 ========")
    def flat(r):
        d = sorted([r[1].x, r[1].y, r[1].z])
        return d[0] / d[2] if d[2] > 1e-9 else 0.0
    rows.sort(key=flat)
    for name, sz, tris in rows[:12]:
        log("  %-46s tris=%-7d size=(%.4f, %.4f, %.4f) flat=%.4f" % (name, tris, sz.x, sz.y, sz.z, flat((name, sz, tris))))


main()
