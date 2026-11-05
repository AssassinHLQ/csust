"""后台批量预览：把爱丽丝的 5 个 glb 各渲染一张图（**不开窗口**）。

用法：
    "D:/SOFTWARE/Blender52/blender.exe" -b --factory-startup \
        -P _tools/preview_glb.py -- <outdir> <glb1> <glb2> ...

说明：
  · 每个模型单独一个空场景，导入后按世界包围盒自动摆相机（3/4 前视）；
  · 引擎优先 EEVEE（会带贴图），失败退回 Workbench（灰模，但形态能看清）；
  · 尺寸 480×640，够认人。
"""

import math
import os
import sys

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    if len(argv) < 2:
        print("用法: ... -- <outdir> <glb...>")
        sys.exit(2)
    return argv[0], argv[1:]


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def is_helper(o):
    """glb 里混着导出时没清掉的辅助物体（Cube / Icosphere，2×2×2），
    它们会把包围盒撑大一倍，取景就跟着跑偏 —— 按名字 + 顶点数/尺寸双重判掉。"""
    nm = o.name
    for bad in ("Cube", "Icosphere", "Plane", "Sphere", "FX_"):
        if nm.startswith(bad):
            return True
    try:
        verts = len(o.data.vertices)
    except Exception:
        verts = 0
    if verts and verts < 50:
        size = o.dimensions
        if max(size.x, size.y, size.z) > 0.5:
            return True
    return False


def world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    found = False
    for o in objs:
        if o.type != "MESH" or is_helper(o):
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
            found = True
    if not found:
        return Vector((0, 0, 0)), 1.0, Vector((1, 1, 1))
    center = (lo + hi) * 0.5
    size = hi - lo
    radius = max(size.length * 0.5, 1e-3)
    return center, radius, size


def setup_lights(center, radius):
    # 只留两盏太阳 + 较亮的环境光。第一版用「按半径平方给能量」的区域灯，
    # 直接曝成惨白；第二版又太暗 —— 这次给固定值。
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", type="SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(55), 0, math.radians(25))
    bpy.context.collection.objects.link(sun)

    rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", type="SUN"))
    rim.data.energy = 1.6
    rim.rotation_euler = (math.radians(65), 0, math.radians(-140))
    bpy.context.collection.objects.link(rim)


def setup_world():
    world = bpy.data.worlds.new("W")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.30, 0.33, 0.38, 1.0)
        bg.inputs[1].default_value = 1.2


def setup_camera(center, radius, direction, ortho_scale):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = center + direction.normalized() * (radius * 6.0)
    look = (center - cam.location)
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render_one(glb, out_png):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = list(bpy.context.scene.objects)
    meshes = [o for o in objs if o.type == "MESH"]
    print("[prev] %s：导入 %d 对象（网格 %d）" % (os.path.basename(glb), len(objs), len(meshes)))

    center, radius, size = world_bbox(meshes)
    setup_lights(center, radius)
    setup_world()

    scene = bpy.context.scene
    scene.render.resolution_x = 480
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    # ⚠️ 默认的 AgX/Filmic 会把二次元贴图洗白，预览用 Standard 更接近原色
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass
    # 竖构图：ortho_scale 对应的是「较长边」（这里是 y=640），
    # 所以取模型**高度**×1.2 就能贴紧；第一版用半径×2.35，人小得看不清。
    ortho = max(size.z, size.x, 1e-3) * 1.2
    print("[prev]   尺寸 %.2f×%.2f×%.2f  正交尺度 %.2f" % (size.x, size.y, size.z, ortho))

    engines = ["BLENDER_EEVEE", "BLENDER_WORKBENCH"]
    base, ext = os.path.splitext(out_png)
    views = [("front", Vector((0.0, -1.0, 0.10))), ("34", Vector((0.85, -1.0, 0.22)))]
    ok = 0
    for tag, direction in views:
        setup_camera(center, radius, direction, ortho)
        scene.render.filepath = "%s_%s%s" % (base, tag, ext)
        for eng in engines:
            try:
                scene.render.engine = eng
                bpy.ops.render.render(write_still=True)
                print("[prev]   ✔ %-6s %s" % (tag, scene.render.filepath))
                ok += 1
                break
            except Exception as e:      # noqa: BLE001
                print("[prev]   ✘ %s/%s 失败：%s" % (eng, tag, e))
    return ok == len(views)


def main():
    outdir, files = parse_args()
    os.makedirs(outdir, exist_ok=True)
    ok = 0
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        safe = name.replace(" ", "_").replace("(", "").replace(")", "")
        out = os.path.join(outdir, "arisu_%s.png" % safe)
        try:
            if render_one(f, out):
                ok += 1
        except Exception as e:      # noqa: BLE001
            print("[prev] !! %s 出错：%s" % (f, e))
    print("[prev] 完成 %d/%d" % (ok, len(files)))


main()
