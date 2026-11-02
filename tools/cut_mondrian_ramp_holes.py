"""在蒙德里安外壳 GLB 的楼板面上，给两段斜坡井开洞。

外壳是实心体量（Base / Mid / Upper），每层的水平面就是两块大三角形。
材质开了双面，从室内看这块面正好盖在斜坡井口上 —— 用户 2026-11-02 截图里
「楼梯全被挡住」的那块板就是它（Mid 底面 y=4.8 / Upper 底面 y=9.2）。

不能对闭合盒做布尔差：盒是实心的，切掉薄薄一层只会留下凹槽，不会开洞。
这里直接删掉那两块大三角形，再按「矩形减去井口」补回四块四边形。

井口尺寸和内衬楼板的洞一致（mondrian_hall.gd）：
  Ramp1: x -7.5~-5.0, z -3.8~2.2, y=4.8  → Base 顶面 + Mid 底面
  Ramp2: x  3.0~ 5.5, z -1.6~3.0, y=9.2  → Mid 顶面 + Upper 底面

用法：
  blender.exe --background --factory-startup \
      --python tools/cut_mondrian_ramp_holes.py
"""
import os

import bmesh
import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLB = os.path.join(ROOT, "models", "mondrian", "mondrian_building.glb")

# (对象, 平面高度, 井口 x0,x1, 井口 godot z0,z1)
JOBS = [
    # 一层地面（Base 底面）整块让给内衬 F1
    ("Base", 0.60, -11.75, 5.75, -7.75, 7.75),
    # 二层地面：Base 顶面 + Mid 底面
    ("Base", 4.80, -7.75, 7.75, -6.75, 6.75),
    ("Mid", 4.80, -7.75, 7.75, -6.75, 6.75),
    # 三层地面：Mid 顶面 + Upper 底面
    ("Mid", 9.20, -4.75, 9.75, -5.75, 4.75),
    ("Upper", 9.20, -4.75, 9.75, -5.75, 4.75),
]


def cut_plane(ob, z_plane, x0, x1, gz0, gz1):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    big = []
    for f in bm.faces:
        c = f.calc_center_median()
        if abs(c.z - z_plane) > 0.03 or abs(f.normal.z) < 0.9:
            continue
        if f.calc_area() < 20.0:
            continue
        big.append(f)
    if not big:
        print("NO_PLANE", ob.name, z_plane)
        bm.free()
        return False
    px0 = min(v.co.x for f in big for v in f.verts)
    px1 = max(v.co.x for f in big for v in f.verts)
    py0 = min(v.co.y for f in big for v in f.verts)
    py1 = max(v.co.y for f in big for v in f.verts)
    mat = big[0].material_index
    # Blender y = -godot z
    hy0, hy1 = -gz1, -gz0
    for f in big:
        bm.faces.remove(f)
    z = z_plane
    verts = {}

    def V(x, y):
        key = (round(x, 5), round(y, 5))
        if key not in verts:
            verts[key] = bm.verts.new((x, y, z))
        return verts[key]

    rects = [
        (px0, px1, py0, hy0),
        (px0, px1, hy1, py1),
        (px0, x0, hy0, hy1),
        (x1, px1, hy0, hy1),
    ]
    for rx0, rx1, ry0, ry1 in rects:
        if rx1 - rx0 < 1e-4 or ry1 - ry0 < 1e-4:
            continue
        nf = bm.faces.new([V(rx0, ry0), V(rx1, ry0), V(rx1, ry1), V(rx0, ry1)])
        nf.material_index = mat
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    print("HOLE", ob.name, "z", z_plane, "plane", (px0, px1, py0, py1),
          "hole", (x0, x1, hy0, hy1))
    return True


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

for name, z, x0, x1, gz0, gz1 in JOBS:
    ob = bpy.data.objects.get(name)
    if ob is None:
        print("MISSING", name)
        continue
    # GLB 导入时对象带着 −90° 旋转，先把变换烘进网格，后面按世界坐标切
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    cut_plane(ob, z, x0, x1, gz0, gz1)

bpy.ops.export_scene.gltf(
    filepath=GLB,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
    export_draco_mesh_compression_enable=False,
    export_animations=False,
    export_lights=False,
    export_cameras=False,
)
print("EXPORTED", GLB, os.path.getsize(GLB))
