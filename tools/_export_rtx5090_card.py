import bpy
import os
from mathutils import Vector

SRC = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/models/rtx5090/RTX5090simplified.obj"
OUT = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/models/rtx5090_card/rtx5090_card.glb"
LEN = 0.40

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=SRC, forward_axis='NEGATIVE_Y', up_axis='Z')
objs = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

lo = Vector((1e9,) * 3)
hi = Vector((-1e9,) * 3)
tris = 0
for o in objs:
    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    for v in o.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
size = hi - lo
center = (lo + hi) * 0.5
s = LEN / max(size)
print("RAW size", tuple(round(v, 2) for v in size), "scale", s, "tris", tris)
for o in objs:
    for v in o.data.vertices:
        v.co = (v.co - center) * s
    o.data.update()

lo2 = Vector((1e9,) * 3)
hi2 = Vector((-1e9,) * 3)
for o in objs:
    for v in o.data.vertices:
        for i in range(3):
            lo2[i] = min(lo2[i], v.co[i])
            hi2[i] = max(hi2[i], v.co[i])
print("CARD size", tuple(round(v, 4) for v in (hi2 - lo2)), "tris", tris)
print("MATS", [m.name for m in bpy.data.materials])
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
