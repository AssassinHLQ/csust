# -*- coding: utf-8 -*-
"""霸王龙优香 · 骨骼动画构建脚本

用法（Blender 5.0）:
    blender -b -P tools/build_trex_yuuka_anims.py

为什么要单独导一份 GLB：
  原始 models/boss/优香霸王龙.fbx 的 73 根骨骼在 **Godot 的 FBX 导入器里会被拍平**
  （所有骨骼静置坐标都变成 0，蒙皮绑定位姿也接近单位矩阵）—— 拿它做动画，整只模型
  会绕原点乱转。Blender 读同一个文件骨骼是正常的（Bone 在 y=-0.34/z=2.0 之类），
  所以动画必须在 Blender 里做，再导出 GLB 给 Godot 用。

骨骼语义（按顶点加权重心反查出来的，改动作时照这张表）:
  Bone.005            下巴        Bone.004        头骨
  Bone.003/.002/.001  颈 → 胸     Bone            胯（根）
  Bone.006 … Bone.012 尾巴 7 节   Bone.013/037    两条后腿大腿
  Bone.023/030        小前肢

产物：models/boss/trex_yuuka_rigged.glb（含 idle/bite/tail_sweep/stomp/charge/roar）
注意：models/boss/** 在 .gitignore 里，GLB 不进仓库，换机器要重跑本脚本。
"""

import bpy, math, os
from mathutils import Vector, Quaternion

SRC = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\boss\优香霸王龙.fbx"
OUT = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\boss\trex_yuuka_rigged.glb"
FPS = 24

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.ops.import_scene.fbx(filepath=SRC, automatic_bone_orientation=False)

arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
arm.name = "TrexRig"
arm.animation_data_create()

JAW = "Bone.005"
SKULL = "Bone.004"
NECK = ["Bone.003", "Bone.002"]
SPINE = ["Bone.001", "Bone"]
TAIL = ["Bone.006", "Bone.007", "Bone.008", "Bone.009", "Bone.010", "Bone.011", "Bone.012"]
LEG_L = ["Bone.013", "Bone.014", "Bone.015", "Bone.016"]
LEG_R = ["Bone.037", "Bone.038", "Bone.039", "Bone.040"]
ARM_L = ["Bone.023", "Bone.024"]
ARM_R = ["Bone.030", "Bone.031"]

AXIS_X = Vector((1, 0, 0))   # 左右轴：绕它转 = 抬头/低头
AXIS_Y = Vector((0, 1, 0))   # 前后轴
AXIS_Z = Vector((0, 0, 1))   # 竖直轴：绕它转 = 左右甩


def reset_pose():
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))


def q(pb, axis, deg):
    """绕**世界轴**转 deg 度，换算成这根骨骼的本地旋转。"""
    m = pb.bone.matrix_local.to_3x3()
    local_axis = (m.inverted() @ axis).normalized()
    return Quaternion(local_axis, math.radians(deg))


def loc_world(pb, offset):
    """世界方向位移换算成骨骼本地平移。"""
    m = pb.bone.matrix_local.to_3x3()
    return m.inverted() @ Vector(offset)


def key_rot(name, frame, axis, deg):
    pb = arm.pose.bones[name]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = q(pb, axis, deg)
    pb.keyframe_insert("rotation_quaternion", frame=frame)


def key_rot2(name, frame, axis_a, deg_a, axis_b, deg_b):
    pb = arm.pose.bones[name]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = q(pb, axis_b, deg_b) @ q(pb, axis_a, deg_a)
    pb.keyframe_insert("rotation_quaternion", frame=frame)


def key_loc(name, frame, offset):
    pb = arm.pose.bones[name]
    pb.location = loc_world(pb, offset)
    pb.keyframe_insert("location", frame=frame)


def key_all_rest(frame, names):
    for nm in names:
        key_rot(nm, frame, AXIS_X, 0.0)


def new_action(name, frames):
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    reset_pose()
    return act


def finish(act, start, end):
    act.use_frame_range = True
    act.frame_start = start
    act.frame_end = end


ALL = [JAW, SKULL] + NECK + SPINE + TAIL + LEG_L + LEG_R + ARM_L + ARM_R

# ── idle：呼吸 + 尾巴行波 ─────────────────────────────────────────────
act = new_action("idle", 96)
for f in range(0, 97, 8):
    t = f / 96.0
    breath = 2.2 * math.sin(2 * math.pi * t)
    key_rot("Bone.001", f, AXIS_X, breath)
    key_rot("Bone.002", f, AXIS_X, breath * 0.7)
    key_rot("Bone.003", f, AXIS_X, -breath * 0.8)
    key_rot(JAW, f, AXIS_X, 3.0 + 2.0 * math.sin(2 * math.pi * t + 1.0))
    for i, nm in enumerate(TAIL):
        phase = 2 * math.pi * t - i * 0.55
        key_rot(nm, f, AXIS_Z, 5.5 * math.sin(phase))
        key_rot2(nm, f, AXIS_Z, 5.5 * math.sin(phase), AXIS_X, 1.6 * math.sin(phase * 0.5))
    key_loc("Bone", f, (0, 0, 0.35 * math.sin(2 * math.pi * t)))
finish(act, 0, 96)
IDLE_RANGE = (0, 96)

# ── bite：张嘴 → 颈前压 → 咬合 ───────────────────────────────────────
act = new_action("bite", 40)
key_all_rest(0, ALL)
key_loc("Bone", 0, (0, 0, 0))
key_rot(JAW, 8, AXIS_X, 24)
key_rot("Bone.003", 8, AXIS_X, 9)
key_rot("Bone.002", 8, AXIS_X, 5)
key_rot("Bone.001", 8, AXIS_X, 4)
key_rot(SKULL, 8, AXIS_X, 6)
key_rot(JAW, 12, AXIS_X, 2)
key_rot("Bone.003", 12, AXIS_X, 16)
key_rot("Bone.002", 12, AXIS_X, 9)
key_rot("Bone.001", 12, AXIS_X, 7)
key_rot(SKULL, 12, AXIS_X, 10)
key_loc("Bone", 12, (0, 0, -0.6))
key_rot(JAW, 20, AXIS_X, 6)
key_rot("Bone.003", 20, AXIS_X, 8)
key_rot("Bone.002", 20, AXIS_X, 4)
key_rot("Bone.001", 20, AXIS_X, 3)
key_rot(SKULL, 20, AXIS_X, 4)
key_loc("Bone", 20, (0, 0, 0))
key_all_rest(32, ALL)
key_loc("Bone", 32, (0, 0, 0))
key_all_rest(40, ALL)
finish(act, 0, 40)

# ── tail_sweep：先蓄力甩一边，再整条尾巴扫回来 ────────────────────────
act = new_action("tail_sweep", 48)
key_all_rest(0, ALL)
key_rot("Bone", 10, AXIS_Z, -16)
for i, nm in enumerate(TAIL):
    key_rot(nm, 10, AXIS_Z, -7 - i * 1.2)
key_rot("Bone.001", 10, AXIS_Z, -6)
key_rot("Bone", 20, AXIS_Z, 22)
for i, nm in enumerate(TAIL):
    key_rot(nm, 20, AXIS_Z, 14 + i * 2.4)
key_rot("Bone.001", 20, AXIS_Z, 8)
key_rot("Bone", 30, AXIS_Z, 12)
for i, nm in enumerate(TAIL):
    key_rot(nm, 30, AXIS_Z, 6 + i * 1.0)
key_rot("Bone.001", 30, AXIS_Z, 4)
key_all_rest(48, ALL)
finish(act, 0, 48)

# ── stomp：抬左腿 → 砸地 → 身体下沉回弹 ─────────────────────────────
act = new_action("stomp", 44)
key_all_rest(0, ALL)
key_loc("Bone", 0, (0, 0, 0))
key_rot("Bone.013", 12, AXIS_X, -26)
key_rot("Bone.014", 12, AXIS_X, 34)
key_rot("Bone.015", 12, AXIS_X, -18)
key_rot("Bone", 12, AXIS_Z, 5)
key_loc("Bone", 12, (0, 0, 0.8))
key_rot("Bone.013", 18, AXIS_X, -34)
key_rot("Bone.014", 18, AXIS_X, 44)
key_rot("Bone.015", 18, AXIS_X, -22)
key_loc("Bone", 18, (0, 0, 1.0))
key_rot("Bone.013", 22, AXIS_X, 0)
key_rot("Bone.014", 22, AXIS_X, 0)
key_rot("Bone.015", 22, AXIS_X, 0)
key_rot("Bone", 22, AXIS_Z, 0)
key_loc("Bone", 22, (0, 0, -1.6))
key_rot("Bone.001", 22, AXIS_X, 5)
key_loc("Bone", 27, (0, 0, -0.6))
key_rot("Bone.001", 27, AXIS_X, 2)
key_loc("Bone", 34, (0, 0, 0))
key_rot("Bone.001", 34, AXIS_X, 0)
key_all_rest(44, ALL)
finish(act, 0, 44)

# ── roar：后仰 + 抬头 + 大张口 ───────────────────────────────────────
act = new_action("roar", 60)
key_all_rest(0, ALL)
key_loc("Bone", 0, (0, 0, 0))
key_rot(JAW, 14, AXIS_X, 30)
key_rot(SKULL, 14, AXIS_X, -16)
key_rot("Bone.003", 14, AXIS_X, -14)
key_rot("Bone.002", 14, AXIS_X, -8)
key_rot("Bone.001", 14, AXIS_X, -5)
key_loc("Bone", 14, (0, 0, 0.6))
key_rot(JAW, 30, AXIS_X, 34)
key_rot(SKULL, 30, AXIS_X, -19)
key_rot("Bone.003", 30, AXIS_X, -16)
key_loc("Bone", 30, (0, 0, 0.8))
key_rot(JAW, 38, AXIS_X, 26)
key_rot(SKULL, 38, AXIS_X, -12)
key_rot("Bone.003", 38, AXIS_X, -10)
key_loc("Bone", 38, (0, 0, 0.5))
key_all_rest(50, ALL)
key_loc("Bone", 50, (0, 0, 0))
key_all_rest(60, ALL)
finish(act, 0, 60)

# ── charge：前倾 + 两条后腿交替蹬地（原地冲锋）──────────────────────
act = new_action("charge", 56)
key_all_rest(0, ALL)
key_loc("Bone", 0, (0, 0, 0))
for f, (l_th, r_th, lift) in [(14, (-28, 26, 0.4)), (26, (26, -28, 0.0)),
                              (38, (-26, 24, 0.4)), (48, (0, 0, 0.0))]:
    key_rot("Bone.013", f, AXIS_X, l_th)
    key_rot("Bone.037", f, AXIS_X, r_th)
    key_rot("Bone.001", f, AXIS_X, 9)
    key_rot("Bone.002", f, AXIS_X, 6)
    key_rot("Bone.003", f, AXIS_X, 10)
    key_rot(JAW, f, AXIS_X, 8)
    for i, nm in enumerate(TAIL):
        key_rot(nm, f, AXIS_X, -2.5 - i * 0.6)
    key_loc("Bone", f, (0, 0, lift))
key_all_rest(56, ALL)
key_loc("Bone", 56, (0, 0, 0))
finish(act, 0, 56)

# 导出前回到静置
arm.animation_data.action = None
reset_pose()

print("ACTIONS_MADE", [(a.name, tuple(round(v, 1) for v in a.frame_range)) for a in bpy.data.actions])

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    use_selection=False,
    export_apply=False,
    export_yup=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_nla_strips=False,
    export_skins=True,
    export_materials='EXPORT',
    export_cameras=False,
    export_lights=False,
)
print("EXPORT_DONE", os.path.getsize(OUT))
