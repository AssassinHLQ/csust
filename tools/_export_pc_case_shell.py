import bpy
import bmesh
import math
import os
from mathutils import Vector

BLEND = r"C:/Users/WY157/Downloads/_pc_case_extract/CUSTOM GAMING PC.blend"
OUT = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/models/pc_case/pc_case_shell.glb"

# 只留外壳 Cube.007
for ob in list(bpy.data.objects):
    if ob.type == 'MESH' and ob.name != "Cube.007":
        bpy.data.objects.remove(ob, do_unlink=True)
    elif ob.type != 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)

ob = bpy.data.objects["Cube.007"]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# 在 +X 侧板开窗（朝房间的那面）
bm = bmesh.new()
bm.from_mesh(ob.data)
del_faces = []
for f in bm.faces:
    c = f.calc_center_median()
    if c.x > 9.55 and -2.935 <= c.y <= 1.21 and -2.354 <= c.z <= 1.74:
        del_faces.append(f)
bmesh.ops.delete(bm, geom=del_faces, context='FACES')
bm.to_mesh(ob.data)
bm.free()
ob.data.update()
print("CUT faces", len(del_faces), "remain", len(ob.data.polygons))

# 统一白漆材质
mat = bpy.data.materials.new("CaseWhite")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.86, 0.88, 0.9, 1.0)
bsdf.inputs["Metallic"].default_value = 0.35
bsdf.inputs["Roughness"].default_value = 0.33
for i in range(len(ob.data.materials)):
    ob.data.materials[i] = mat
if len(ob.data.materials) == 0:
    ob.data.materials.append(mat)

# 旋转 +90°：开窗面朝 glTF 的 -Z（Godot 朝房间）
ob.rotation_euler[2] = math.radians(90)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
ob.scale = (0.1, 0.1, 0.1)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# 以包围盒中心为原点
lo = Vector((1e9,) * 3)
hi = Vector((-1e9,) * 3)
for v in ob.data.vertices:
    for i in range(3):
        lo[i] = min(lo[i], v.co[i])
        hi[i] = max(hi[i], v.co[i])
center = (lo + hi) * 0.5
for v in ob.data.vertices:
    v.co -= center
ob.data.update()

dims = hi - lo
tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
print("SHELL dims %.4f %.4f %.4f  tris %d" % (dims.x, dims.y, dims.z, tris))
print("SHELL bounds lo", tuple(round(v, 4) for v in (lo - center)),
      "hi", tuple(round(v, 4) for v in (hi - center)))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_materials='EXPORT',
)
print("WROTE", OUT, os.path.getsize(OUT))
