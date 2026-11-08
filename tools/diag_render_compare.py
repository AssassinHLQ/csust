"""对比渲染：把原始 FBX 和导出的 GLB 各渲一张等角视图，肉眼对比。

  & blender -b --python tools\\diag_render_compare.py -- <fbx> <glb> <输出目录>

出图：
  fbx_iso.png   原始 FBX
  glb_iso.png   导出 GLB
  fbx_side.png / glb_side.png
"""

import sys
import os
import math

import bpy
import mathutils


def log(m):
    print("[cmp] %s" % m)


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_scene():
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.resolution_x = 1280
    scn.render.resolution_y = 720
    scn.render.film_transparent = False
    scn.world = bpy.data.worlds.new("W")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.05, 0.06, 0.09, 1.0)
    bg.inputs[1].default_value = 1.0

    # 太阳光
    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    scn.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))

    # 补光
    area_data = bpy.data.lights.new("Area", type="AREA")
    area_data.energy = 3000
    area_data.size = 30
    area = bpy.data.objects.new("Area", area_data)
    scn.collection.objects.link(area)
    area.location = (20, -20, 25)
    area.rotation_euler = (math.radians(45), 0, math.radians(45))


def world_bounds(meshes):
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = mathutils.Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        mw = o.matrix_world
        for c in o.bound_box:
            p = mw @ mathutils.Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return lo, hi


def render_view(out_path, cam_loc, target):
    scn = bpy.context.scene
    cam_data = bpy.data.cameras.new("C")
    cam_data.lens = 35
    cam = bpy.data.objects.new("C", cam_data)
    scn.collection.objects.link(cam)
    cam.location = cam_loc
    d = mathutils.Vector(target) - mathutils.Vector(cam_loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam

    scn.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    log("渲染 %s" % out_path)

    bpy.data.objects.remove(cam, do_unlink=True)


def do_render(tag, importer, src, outdir):
    clear()
    setup_scene()
    log("%s: 导入 %s" % (tag, src))
    if importer == "fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    else:
        bpy.ops.import_scene.gltf(filepath=src)
    bpy.context.view_layer.update()

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo, hi = world_bounds(meshes)
    cen = (lo + hi) * 0.5
    size = hi - lo
    log("%s: bounds min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)"
        % (tag, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, size.x, size.y, size.z))

    r = max(size.x, size.y, size.z)
    os.makedirs(outdir, exist_ok=True)
    # 等角
    render_view(os.path.join(outdir, "%s_iso.png" % tag),
                (cen.x + r * 0.9, cen.y - r * 0.9, cen.z + r * 0.8), cen)
    # 侧面（高度方向看）
    render_view(os.path.join(outdir, "%s_side.png" % tag),
                (cen.x + r * 1.3, cen.y, cen.z + r * 0.15), cen)


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(args) < 3:
        log("用法：blender -b --python diag_render_compare.py -- <fbx> <glb> <outdir>")
        return
    fbx, glb, outdir = args[0], args[1], args[2]
    do_render("fbx", "fbx", fbx, outdir)
    do_render("glb", "glb", glb, outdir)


main()
