"""把用户 Rhino 导出的 9950X3D GLB 做成游戏就绪版（v2）。

输入：_tmp_cpu9950/ryzen_rhino.glb（Rhino 导出：主体 70,572 面 + 395 个亚毫米碎件）
做法：
  · 只保留主体，按面高度分材质（基板蓝 / IHS 银），Decimate 到 ~1.2 万面
  · 碎件全部丢掉，按封装箱尺寸重新生成 32 颗金手指（每颗 12 面）
  · 顶点级缩放到 12 cm 见方、底面落在 z=0
  · 顶面贴 IHS 丝印（ihs_label.png）
输出：models/cpu_9950x3d/ryzen_9950x3d.glb
    D:/SOFTWARE/Blender52/blender.exe -b --python tools/build_9950x3d_rhino.py
"""
import bpy
import bmesh
import os
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = r"C:\Users\WY157\Desktop\GODOT\_tmp_cpu9950\ryzen_rhino.glb"
DST = os.path.join(ROOT, "models", "cpu_9950x3d", "ryzen_9950x3d.glb")
LABEL = os.path.join(ROOT, "models", "cpu_9950x3d", "ihs_label.png")
TARGET_TRIS = 12000
Z_SPLIT = -0.0179      # 基板顶面（源模型世界坐标）
TARGET_WIDTH = 0.12

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
big = max(objs, key=lambda o: len(o.data.polygons))
for o in objs:
    if o is not big:
        bpy.data.objects.remove(o, do_unlink=True)
print("[9950] 只留主体：%d 面" % len(big.data.polygons))


def make_mat(name, color, metallic=0.0, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m


blue = make_mat("CPU_PCB", (0.045, 0.16, 0.42), 0.15, 0.42)
silver = make_mat("CPU_IHS", (0.66, 0.68, 0.71), 0.85, 0.30)
gold = make_mat("CPU_Gold", (0.85, 0.66, 0.22), 1.0, 0.30)
big.data.materials.clear()
big.data.materials.append(blue)
big.data.materials.append(silver)
big.data.materials.append(gold)

# 先烘掉导入的节点变换，再按世界高度分色
bpy.ops.object.select_all(action='DESELECT')
big.select_set(True)
bpy.context.view_layer.objects.active = big
# glTF 的节点带父子缩放：先保持世界变换解父，再把变换烘进网格
mw = big.matrix_world.copy()
big.parent = None
big.matrix_world = mw
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# ⚠️ glTF 的顶点是按法线拆开的，直接 Decimate 会把网格撕成巨大退化三角形
#    （实测包围盒从 40 mm 涨到 157 mm）。先按距离焊接，再减面。
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.000005)
bpy.ops.object.mode_set(mode='OBJECT')
print("[9950] 焊接后 %d 面" % len(big.data.polygons))
for p in big.data.polygons:
    p.material_index = 0 if p.center.z < Z_SPLIT else 1

# 减面
mod = big.modifiers.new("Decimate", "DECIMATE")
mod.ratio = min(1.0, TARGET_TRIS / float(len(big.data.polygons)))
bpy.ops.object.modifier_apply(modifier=mod.name)
print("[9950] 减面后 %d 面" % len(big.data.polygons))

# 顶点级缩放：12 cm 见方、xy 居中、底面 z=0
vs = [v.co.copy() for v in big.data.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
s = TARGET_WIDTH / max(hi.x - lo.x, hi.y - lo.y)
cx = (lo.x + hi.x) * 0.5
cy = (lo.y + hi.y) * 0.5
for v in big.data.vertices:
    v.co = Vector(((v.co.x - cx) * s, (v.co.y - cy) * s, (v.co.z - lo.z) * s))
big.data.update()
zs = [v.co.z for v in big.data.vertices]
print("[9950] 缩放 %.3f×：12 cm 见方、厚 %.1f mm" % (s, (max(zs) - min(zs)) * 1000))

# 金手指：直接写进同一张网格（32 颗 × 12 面）
bm = bmesh.new()
bm.from_mesh(big.data)
pcb_top = (Z_SPLIT - lo.z) * s
pad_w, pad_t, pad_h = 0.008, 0.0018, 0.0018
for side in range(4):
    for i in range(8):
        t = -0.045 + i * 0.01285
        if side == 0:
            c, sz = Vector((0.055, t, pcb_top + 0.0009)), Vector((pad_w, 0.005, pad_h))
        elif side == 1:
            c, sz = Vector((-0.055, t, pcb_top + 0.0009)), Vector((pad_w, 0.005, pad_h))
        elif side == 2:
            c, sz = Vector((t, 0.055, pcb_top + 0.0009)), Vector((0.005, pad_w, pad_h))
        else:
            c, sz = Vector((t, -0.055, pcb_top + 0.0009)), Vector((0.005, pad_w, pad_h))
        mat = Matrix.Translation(c) @ Matrix.Diagonal((sz.x, sz.y, sz.z, 1.0))
        res = bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
        for f in res["verts"][0].link_faces:
            f.material_index = 2
bm.to_mesh(big.data)
bm.free()
big.data.update()
print("[9950] 金手指 32 颗；合计 %d 面" % len(big.data.polygons))

# IHS 丝印贴图
img = bpy.data.images.load(LABEL, check_existing=True)
label_mat = bpy.data.materials.new("CPU_Label")
label_mat.use_nodes = True
nt = label_mat.node_tree
b = nt.nodes["Principled BSDF"]
t = nt.nodes.new("ShaderNodeTexImage")
t.image = img
t.interpolation = "Linear"
nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
b.inputs["Metallic"].default_value = 0.25
b.inputs["Roughness"].default_value = 0.35
top = max(zs)
bpy.ops.mesh.primitive_plane_add(size=0.088, location=(0.0, 0.0, top + 0.00035))
plane = bpy.context.object
plane.name = "IHS_Label"
plane.data.materials.append(label_mat)

bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_apply=True)
print("[9950] 导出：%s" % DST)
