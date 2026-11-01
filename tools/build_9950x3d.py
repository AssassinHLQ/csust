"""生成 AMD Ryzen 9 9950X3D 低模（GLB）。

用户给了爱给网的 SolidWorks 源文件（`.SLDPRT`，Godot/Blender 都读不了），
这里按同目录的参考图 `P1.PNG` 重建一个游戏用低模：
蓝色基板 + 银色 IHS + 四排金手指 + IHS 丝印（Pillow 生成的贴图）。

    D:/SOFTWARE/Blender/blender.exe -b --python tools/build_9950x3d.py
产物：models/cpu_9950x3d/ryzen_9950x3d.glb
"""
import bpy
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "models", "cpu_9950x3d", "ryzen_9950x3d.glb")
LABEL = os.path.join(ROOT, "models", "cpu_9950x3d", "ihs_label.png")

bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, color, metallic=0.0, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return m


def add_box(name, loc, size, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
    o.data.materials.append(material)
    return o


pcb = make_mat("CPU_PCB", (0.045, 0.16, 0.42), 0.15, 0.42)
silver = make_mat("CPU_IHS", (0.66, 0.68, 0.71), 0.9, 0.28)
gold = make_mat("CPU_Gold", (0.85, 0.66, 0.22), 1.0, 0.3)

# 基板 120 x 120 x 4 mm（游戏里比真 CPU 大一圈，桌面上看得清）
add_box("PCB", (0.0, 0.0, 0.002), (0.12, 0.12, 0.004), pcb, bevel=0.003)
# IHS 90 x 90 x 4 mm
add_box("IHS", (0.0, 0.0, 0.006), (0.09, 0.09, 0.004), silver, bevel=0.004)

# 四排金手指（每排 8 颗）
for side in range(4):
    for i in range(8):
        t = -0.045 + i * 0.0128
        if side == 0:
            loc, size = (0.054, t, 0.0026), (0.006, 0.004, 0.0012)
        elif side == 1:
            loc, size = (-0.054, t, 0.0026), (0.006, 0.004, 0.0012)
        elif side == 2:
            loc, size = (t, 0.054, 0.0026), (0.004, 0.006, 0.0012)
        else:
            loc, size = (t, -0.054, 0.0026), (0.004, 0.006, 0.0012)
        add_box("Pad_%d_%d" % (side, i), loc, size, gold)

# 角上的金色三角定位标记
bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=0.007, depth=0.0008,
                                location=(0.031, 0.031, 0.0082))
tri = bpy.context.object
tri.name = "OrientationTri"
tri.rotation_euler = (0.0, 0.0, 0.0)
tri.data.materials.append(gold)

# IHS 丝印贴图（贴在 IHS 顶面上方 0.06 mm）
img = bpy.data.images.load(LABEL, check_existing=True)
label_mat = bpy.data.materials.new("CPU_Label")
label_mat.use_nodes = True
nt = label_mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
tex.interpolation = "Linear"
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Metallic"].default_value = 0.2
bsdf.inputs["Roughness"].default_value = 0.35

bpy.ops.mesh.primitive_plane_add(size=0.086, location=(0.0, 0.0, 0.00804))
plane = bpy.context.object
plane.name = "IHS_Label"
plane.data.materials.append(label_mat)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# 导出（嵌贴图）
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True)
print("[9950X3D] 导出：%s" % OUT)
