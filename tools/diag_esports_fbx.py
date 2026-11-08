"""诊断：原始 FBX 到底是什么形状。

不做任何处理，只导入 + 打印：
  · 总包围盒 / 尺寸
  · 每个对象的尺寸（找出「压扁成板」的对象）
  · 有多少对象是「薄片」（某一维 < 1cm）

用法：
  & "D:\\SOFTWARE\\Blender52\\blender.exe" -b --python tools\\diag_esports_fbx.py -- "C:\\Users\\WY157\\Desktop\\游戏开发电竞房.fbx"
"""

import sys
import os

import bpy


def log(msg):
    print("[diag] %s" % msg)


def tri_count(o):
    return len(o.data.loop_triangles) if o.data.loop_triangles else len(o.data.polygons)


def measure(o):
    """返回对象在**世界坐标**下的 AABB 尺寸。"""
    import mathutils
    mw = o.matrix_world
    pts = [mw @ mathutils.Vector(c) for c in o.bound_box]
    mn = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx, (mx - mn)


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    if not args:
        log("用法：blender -b --python diag_esports_fbx.py -- <fbx>")
        return
    src = args[0]
    if not os.path.exists(src):
        log("找不到 %s" % src)
        return

    bpy.ops.wm.read_factory_settings(use_empty=True)
    log("导入 %s（%.1f MB）" % (src, os.path.getsize(src) / 1e6))
    bpy.ops.import_scene.fbx(filepath=src)
    bpy.context.view_layer.update()

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    log("对象数 = %d" % len(meshes))

    # 算三角面
    total_tris = 0
    for o in meshes:
        me = o.data
        me.calc_loop_triangles()
        total_tris += len(me.loop_triangles)
    log("三角面总数 = %d" % total_tris)

    # 全局包围盒
    gmn = None
    gmx = None
    rows = []
    for o in meshes:
        mn, mx, sz = measure(o)
        if gmn is None:
            gmn, gmx = mn.copy(), mx.copy()
        else:
            gmn.x = min(gmn.x, mn.x); gmn.y = min(gmn.y, mn.y); gmn.z = min(gmn.z, mn.z)
            gmx.x = max(gmx.x, mx.x); gmx.y = max(gmx.y, mx.y); gmx.z = max(gmx.z, mx.z)
        rows.append((o.name, sz.x, sz.y, sz.z, tri_count(o),
                     o.scale.x, o.scale.y, o.scale.z))

    log("======== 全局 ========")
    log("min = (%.3f, %.3f, %.3f)" % (gmn.x, gmn.y, gmn.z))
    log("max = (%.3f, %.3f, %.3f)" % (gmx.x, gmx.y, gmx.z))
    log("SIZE = (%.3f, %.3f, %.3f)" % (gmx.x - gmn.x, gmx.y - gmn.y, gmx.z - gmn.z))

    # 统计「薄片」
    thin_x = sum(1 for r in rows if r[1] < 0.01)
    thin_y = sum(1 for r in rows if r[2] < 0.01)
    thin_z = sum(1 for r in rows if r[3] < 0.01)
    log("薄片（某维 < 1cm）：X %d / Y %d / Z %d，共 %d 个对象" % (thin_x, thin_y, thin_z, len(rows)))

    # 面数最多的 20 件，看它们的尺寸
    log("======== 面数最多的 20 件（看尺寸是否合理） ========")
    rows.sort(key=lambda r: -r[4])
    for r in rows[:20]:
        log("%-48s tris=%-7d size=(%.3f, %.3f, %.3f) scale=(%.3f, %.3f, %.3f)"
            % (r[0], r[4], r[1], r[2], r[3], r[5], r[6], r[7]))

    # 尺寸最扁的 12 件（按最小维度 / 最大维度）
    log("======== 最扁的 12 件（min_dim/max_dim 最小） ========")
    def flatness(r):
        dims = sorted([r[1], r[2], r[3]])
        if dims[2] < 1e-9:
            return 0.0
        return dims[0] / dims[2]
    rows.sort(key=flatness)
    for r in rows[:12]:
        log("%-48s tris=%-7d size=(%.4f, %.4f, %.4f) flat=%.4f"
            % (r[0], r[4], r[1], r[2], r[3], flatness(r)))

    # 负缩放检查（镜像会翻法线）
    neg = [r for r in rows if r[5] < 0 or r[6] < 0 or r[7] < 0]
    log("======== 负缩放对象 = %d 个 ========" % len(neg))
    for r in neg[:15]:
        log("%-48s scale=(%.3f, %.3f, %.3f)" % (r[0], r[5], r[6], r[7]))


main()
