import bpy
import os
from mathutils import Vector

SRC = r"C:/Users/WY157/Downloads/29 显示器 屏幕_爱给网_aigei_com/AM261_029.fbx"
OUT = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/models/monitor/monitor.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
objs = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# 玻璃面板删掉：屏幕本身保留，避免 GLB 透明排序把画面盖住
for o in list(bpy.data.objects):
    if o.type == 'MESH' and 'glass_screen' in o.name:
        bpy.data.objects.remove(o, do_unlink=True)
objs = [o for o in bpy.data.objects if o.type == 'MESH']


def make_mat(name, color, metal, rough, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


white = make_mat("MonitorWhite", (0.87, 0.89, 0.91), 0.10, 0.34)
dark = make_mat("MonitorDark", (0.025, 0.03, 0.035), 0.25, 0.45)
silver = make_mat("MonitorSilver", (0.60, 0.62, 0.65), 0.80, 0.28)
screen = make_mat("MonitorScreen", (0.01, 0.025, 0.05), 0.0, 0.15,
                  emit=(0.04, 0.14, 0.30), emit_strength=1.4)
cyan = make_mat("MonitorRGB", (0.02, 0.03, 0.04), 0.0, 0.3,
                emit=(0.10, 0.80, 1.0), emit_strength=2.0)

for o in objs:
    n = o.name.lower()
    if "plastic_001" in n:
        m = white
    elif "plastic_002" in n:
        m = dark
    elif "emissive" in n:
        m = cyan
    elif "screen" in n:
        m = screen
    elif "metal" in n:
        m = silver
    else:
        m = dark
    o.data.materials.clear()
    o.data.materials.append(m)

# 以脚底中心为原点（Blender Z 向上；GLB 导出后 Y 向上）
lo = Vector((1e9,) * 3)
hi = Vector((-1e9,) * 3)
for o in objs:
    for v in o.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
cx = (lo.x + hi.x) * 0.5
cy = (lo.y + hi.y) * 0.5
for o in objs:
    for v in o.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= lo.z
    o.data.update()
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
print("MONITOR size", tuple(round(v, 4) for v in (hi - lo)), "bottom", round(lo.z, 4), "tris", tris)
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
