"""验：导出的 `models/esports_room/esports_room.glb` 面数分布 / 材质 / 贴图 / 包围盒。

用法：
    D:/SOFTWARE/Blender52/blender.exe --background --factory-startup \
        --python tools/check_esports_glb.py -- models/esports_room/esports_room.glb
只读。
"""
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
argv = sys.argv
SRC = argv[argv.index("--") + 1] if "--" in argv and len(argv) > argv.index("--") + 1 else \
    os.path.join(ROOT, "models", "esports_room", "esports_room.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


total = sum(tris(o) for o in meshes)
print("[glb] %s  %.1f MB / %d 对象 / %d 三角面" % (os.path.basename(SRC),
      os.path.getsize(SRC) / 1e6, len(meshes), total))

lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i])
            hi[i] = max(hi[i], w[i])
print("[glb] 包围盒 min=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % (
    lo.x, lo.y, lo.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))

rows = sorted(((tris(o), o.name, len(o.data.vertices)) for o in meshes), reverse=True)
print("[glb] ── 全部对象（名字 / 面数 / 世界 AABB）──")
for o in sorted(meshes, key=lambda x: x.name):
    a, b = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            a[i] = min(a[i], w[i])
            b[i] = max(b[i], w[i])
    print("   %-38s %7d 面   min=(%6.2f,%5.2f,%6.2f) size=(%5.2f,%5.2f,%5.2f)" % (
        o.name[:38], tris(o), a.x, a.y, a.z, b.x - a.x, b.y - a.y, b.z - a.z))
print("[glb] 面数最大的 8 件：")
for t, n, v in rows[:8]:
    print("   %8d 面  %-40s %d 顶点" % (t, n, v))
print("[glb] 小件合计：%d 件 / %d 面（<400 面）" % (
    sum(1 for t, _, _ in rows if t < 400), sum(t for t, _, _ in rows if t < 400)))

imgs = [i for i in bpy.data.images if i.size[0] > 0]
print("[glb] 贴图 %d 张：" % len(imgs))
for i in imgs:
    print("   %-40s %dx%d packed=%s" % (i.name[:40], i.size[0], i.size[1], i.packed_file is not None))

odd = 0
for o in meshes:
    for s in o.material_slots:
        m = s.material
        if m is None:
            continue
        for n in m.node_tree.nodes if m.use_nodes else []:
            if n.type == "TEX_IMAGE" and (n.image is None or n.image.size[0] == 0):
                odd += 1
print("[glb] 指向空贴图的采样节点 %d 个" % odd)
