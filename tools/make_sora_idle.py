"""给小空做**待机动画**并导出 GLB（Blender 5.0 无头）—— v3：切到 FK 再摆。

── 这套 rig 为什么这么难摆（三轮才摸清）──
变形骨不是链式父子，全靠约束复制：
    arm.l      ←arm_ik.l（influence 1）/ ←arm_fk.l（influence 0）
    forearm.l  ←forearm_ik.l / ←forearm_fk.l
    hand.l     ←c_hand_ik.l + COPY_LOCATION←forearm_ik.l
而且 hand.l 的父级是 forearm.l、forearm.l 的父级是 c_traj（根）——**层级是断的**。
所以：
  · 掰 FK 控制骨没反应（FK 那条链权重 0，IK 才是 1）→ 必须在脚本里**切到 FK**；
  · 光切 arm.l 不够，forearm/hand 的 IK 约束也要一起关，否则前臂和手留在原地；
  · 直接搬 IK 手控骨会被 IK 链路钳住（目标 0.49 只到 0.70，还把手甩到身体中线）。

v3 做法：把六根变形骨上的 `*_ik` 约束全部归零、`*_fk` 全部置 1，让整条 FK 链
（c_arm_fk → arm_fk → c_forearm_fk → forearm_fk → c_hand_fk）接管，
然后用 FK 控制骨摆一个**手自然下垂**的姿势，再打 48 帧呼吸循环。

用法：
    blender.exe --background "<小空1donzuo.blend>" --python tools/make_sora_idle.py -- <out.glb>
"""
import math
import sys

import bpy
from mathutils import Quaternion, Vector

OUT = sys.argv[-1]
if not OUT.lower().endswith(".glb"):
    raise SystemExit("用法：--python make_sora_idle.py -- <out.glb>")

FPS = 24
FRAMES = 48
ARM_DROP = 62.0        # 上臂往下转（FK，度）
FOREARM_BEND = 8.0     # 肘微屈

rig = bpy.data.objects["rig"]
scene = bpy.context.scene
scene.render.fps = FPS

for o in list(bpy.data.objects):
    if o.name.startswith("cs_"):
        bpy.data.objects.remove(o, do_unlink=True)
for act in list(bpy.data.actions):
    if rig.animation_data and rig.animation_data.action == act:
        rig.animation_data.action = None
    bpy.data.actions.remove(act)


def upd():
    bpy.context.view_layer.update()


# ── 1) 切 FK ──
print("=== 切 FK ===")
for bone_name in ["arm.l", "arm.r", "forearm.l", "forearm.r", "hand.l", "hand.r"]:
    pb = rig.pose.bones.get(bone_name)
    if pb is None:
        continue
    for c in pb.constraints:
        if c.type not in {'COPY_ROTATION', 'COPY_LOCATION', 'COPY_SCALE'}:
            continue
        sub = (getattr(c, "subtarget", "") or "").lower()
        if "_ik" in sub:
            c.influence = 0.0
        elif "_fk" in sub:
            c.influence = 1.0
    print("  %-10s -> %s" % (bone_name,
          ", ".join("%s<-%s:%.2f" % (c.type[:4], getattr(c, "subtarget", ""), c.influence)
                    for c in pb.constraints)))
upd()


def hand_pos(side):
    upd()
    return (rig.matrix_world @ rig.pose.bones["hand." + side].head).copy()


print("=== 切 FK 后 hand.l =", tuple(round(v, 3) for v in hand_pos("l")))
print("=== 切 FK 后 hand.r =", tuple(round(v, 3) for v in hand_pos("r")))


# ── 2) 摆姿势：上臂往下转，肘微屈 ──
def local_axis_towards_down(pb):
    R = pb.bone.matrix_local.to_3x3()
    arm_dir = (R @ Vector((0.0, 1.0, 0.0))).normalized()
    axis = arm_dir.cross(Vector((0.0, 0.0, -1.0)))
    if axis.length < 1e-6:
        axis = Vector((0.0, 1.0, 0.0))
    axis.normalize()
    return (R.inverted() @ axis).normalized()


for side in ("l", "r"):
    for name, deg in (("c_arm_fk." + side, ARM_DROP),
                      ("c_forearm_fk." + side, FOREARM_BEND)):
        pb = rig.pose.bones.get(name)
        if pb is None:
            continue
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion(local_axis_towards_down(pb), math.radians(deg))
upd()
print("=== 摆完后 hand.l =", tuple(round(v, 3) for v in hand_pos("l")))
print("=== 摆完后 hand.r =", tuple(round(v, 3) for v in hand_pos("r")))

# ── 3) 待机关键帧 ──
rig.animation_data_create()
action = bpy.data.actions.new("Idle")
rig.animation_data.action = action
action.use_fake_user = True

base_q = {}
for name in ["c_spine_01.x", "c_spine_02.x", "c_spine_03.x", "c_head.x",
             "c_arm_fk.l", "c_arm_fk.r"]:
    pb = rig.pose.bones.get(name)
    if pb:
        pb.rotation_mode = 'QUATERNION'
        base_q[name] = pb.rotation_quaternion.copy()

KEYS = [(1, 0.0), (13, 1.0), (25, 0.0), (37, -1.0), (49, 0.0)]


def key_bone(name, axis, deg, frame, ph):
    pb = rig.pose.bones.get(name)
    if pb is None or name not in base_q:
        return
    pb.rotation_quaternion = base_q[name] @ Quaternion(axis, math.radians(deg * ph))
    pb.keyframe_insert("rotation_quaternion", frame=frame)


for frame, ph in KEYS:
    scene.frame_set(frame)
    key_bone("c_spine_02.x", Vector((1, 0, 0)), 1.5, frame, ph)
    key_bone("c_spine_01.x", Vector((0, 1, 0)), 0.7, frame, ph)
    key_bone("c_head.x", Vector((0, 1, 0)), 1.8, frame, ph)
    for side in ("l", "r"):
        pb = rig.pose.bones.get("c_arm_fk." + side)
        if pb is None:
            continue
        key_bone("c_arm_fk." + side, local_axis_towards_down(pb), 1.6, frame, ph)

scene.frame_start = 1
scene.frame_end = FRAMES + 1
scene.frame_set(1)

# ── 4) 导出 ──
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

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_force_sampling=True,
    export_rest_position_armature=False,
    export_yup=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
)
print("=== 导出完成 ===", OUT)
print("=== 动作 ===", [a.name for a in bpy.data.actions])
