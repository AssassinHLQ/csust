# -*- coding: utf-8 -*-
"""把 GLB 里每个「材质桶」单独拍一张小图 —— 用**无光照**的 workbench，
只看 albedo 贴图对不对（Rhino 那套贴图路径要是没打包成功，这里就是一片纯色）。

    blender -b -P tools/preview_esports_materials.py -- models/esports_room/esports_room.glb
输出：_arisu_captures/_esports_new/mat_XX_<名字>.png

本喵没有图像识别能力，看不了渲出来的图；所以这个脚本同时把
「材质 → 贴图」清单打到 stdout，本喵读清单、使用者看图，两边对得上。
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
OUT = os.path.join(ROOT, "_arisu_captures", "_esports_new")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = sorted([o for o in bpy.context.scene.objects if o.type == "MESH"], key=lambda o: o.name)
print("[mat] %d 个对象" % len(meshes))

for o in meshes:
    m = o.material_slots[0].material if o.material_slots else None
    tex = "—"
    base = "—"
    if m is not None:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image is not None:
                    tex = "%s %dx%d" % (n.image.name, n.image.size[0], n.image.size[1])
                    break
        base = "%.2f,%.2f,%.2f" % tuple(m.diffuse_color[:3])
    print("[mat] %-38s ← %-28s base=%s" % (o.name[:38], tex, base))

os.makedirs(OUT, exist_ok=True)
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
sh = scn.display.shading
sh.light = "FLAT"
sh.color_type = "TEXTURE"
scn.render.resolution_x = 320
scn.render.resolution_y = 240
scn.render.film_transparent = False
if scn.world is None:
    scn.world = bpy.data.worlds.new("W")
scn.world.color = (0.12, 0.12, 0.14)

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_data)
scn.collection.objects.link(cam)
scn.camera = cam

for idx, o in enumerate(meshes):
    a = Vector((1e9, 1e9, 1e9))
    b = Vector((-1e9, -1e9, -1e9))
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            a[i] = min(a[i], w[i])
            b[i] = max(b[i], w[i])
    ctr = (a + b) * 0.5
    diag = max((b - a).length, 0.05)
    cam_data.ortho_scale = diag * 1.15
    cam.location = ctr + Vector((0.0, 0.0, diag * 2.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    for other in meshes:
        other.hide_render = other is not o
    safe = "".join(ch if ch.isalnum() or ch in "-_." else "_" for ch in o.name)[:24]
    scn.render.filepath = os.path.join(OUT, "mat_%02d_%s.png" % (idx, safe))
    bpy.ops.render.render(write_still=True)

for other in meshes:
    other.hide_render = False
print("[mat] 完事，%d 张图在 %s" % (len(meshes), OUT))
