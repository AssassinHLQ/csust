"""把用户给的 `.blend`（天使24 店员「小空」）导出成 Godot 能读的 GLB。

用法（Blender 5.0，无头）：
    blender.exe --background "<小空1donzuo.blend>" --python tools/export_sora_glb.py -- <out.glb>

做三件事：
  1. 删掉 `cs_*` 控制方块（那套 Maya rig 的可视化控制器，几十个网格，不能进游戏）；
  2. 只留「骨架 + 带 Armature 修改器（或 MIRROR）的网格」，相机/灯/集合外的东西全部剔除；
  3. `export_rest_position_armature=False` —— 用**当前姿态**当静止姿态，保住作者的 A-pose
     （否则导回去是 T-pose，比 A-pose 更难看）。

⚠️ 这套 rig 导成 glTF 之后变形骨之间**不是链式父子关系**（原工程靠约束/IK 驱动），
   所以进 Godot 以后不能再掰骨头摆姿势；要别的姿势得回 Blender 做好再导。
   小空站在柜台后面，双手 0.89 / 0.69 m 低于台面 1.04 m，A-pose 正好被挡住。

⚠️ 素材是第三方二创（作者：薛定谔的小问号），只在本地学习用；`models/npc/` 已被
   `.gitignore` 排除，不随仓库分发。署名见 CREDITS.md。
"""
import sys

import bpy

out = sys.argv[-1]
if not out.lower().endswith(".glb"):
    raise SystemExit("用法：--python export_sora_glb.py -- <xxx.glb>")

# 1) 控制方块 / 相机 / 灯
for o in list(bpy.data.objects):
    if o.name.startswith("cs_") or o.type in {'CAMERA', 'LIGHT'}:
        bpy.data.objects.remove(o, do_unlink=True)

# 2) 骨架 + 变形网格
keep = []
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        keep.append(o)
    elif o.type == 'MESH' and any(m.type in {'ARMATURE', 'MIRROR'} for m in o.modifiers):
        keep.append(o)

for o in bpy.data.objects:
    o.select_set(False)
for o in keep:
    o.select_set(True)
bpy.context.view_layer.objects.active = keep[0] if keep else None

print("=== 导出对象 %d 个 ===" % len(keep))
for o in keep:
    print("  ", o.type, o.name)

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format='GLB',
    use_selection=True,
    export_apply=True,                 # 把 NODES/SOLIDIFY/SUBSURF 烘进去（Armature 保留）
    export_animations=False,
    export_rest_position_armature=False,
    export_yup=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
)
print("=== 已导出 ===", out)
