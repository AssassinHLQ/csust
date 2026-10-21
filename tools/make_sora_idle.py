"""给小空做**待机动画**并导出 GLB（Blender 5.0 无头）。

── 这套 rig 到底怎么驱动（探出来的，别再猜）──
    变形骨 `arm.l` / `forearm.l` / `hand.l` 全都靠 **约束** 从 IK 控制骨复制：
        forearm_ik.l  ── IK 约束，target = c_hand_ik.l
        hand.l        ── Copy Rotation ← c_hand_ik.l / Copy Location ← forearm_ik.l
    FK 那条链（c_arm_fk → arm_fk → arm.l）的 Copy Rotation **influence = 0**，
    也就是**现在是 IK 模式**。所以掰 FK 一点用都没有（实测 hand 世界坐标纹丝不动），
    只能**搬 IK 手控骨 `c_hand_ik.l/.r`**。

── 做法 ──
    1. 用 6 次迭代把两只手"按"到胯高（求解 IK 目标的位置，不是硬塞一个常量）；
    2. 在 48 帧（2 秒，24 fps）上打关键帧：呼吸（胸椎 ±1.4°）、头慢半拍摆 ±1.8°、
       两只手随呼吸轻轻起伏 ±1 cm；首尾同帧 → 无缝循环；
    3. 只导出 `Idle` 一个动作（文件里另有 Cube/rig/rigAction 三个垃圾动作，删掉）。

用法：
    blender.exe --background "<小空1donzuo.blend>" --python tools/make_sora_idle.py -- <out.glb>
"""
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

OUT = sys.argv[-1]
if not OUT.lower().endswith(".glb"):
    raise SystemExit("用法：--python make_sora_idle.py -- <out.glb>")

FPS = 24
FRAMES = 48
HAND_DROP_Z = 0.40      # 手往下压多少（世界 Z，Blender 是 Z-up）
HAND_PULL_X = 0.06      # 手往身体内侧收多少

rig = bpy.data.objects["rig"]
scene = bpy.context.scene
scene.render.fps = FPS

# 控制方块 cs_* 只是可视化，导不进游戏
for o in list(bpy.data.objects):
    if o.name.startswith("cs_"):
        bpy.data.objects.remove(o, do_unlink=True)

# 清掉文件里自带的垃圾动作，只留我们自己做的
for act in list(bpy.data.actions):
    if rig.animation_data and rig.animation_data.action == act:
        rig.animation_data.action = None
    bpy.data.actions.remove(act)


def upd():
    bpy.context.view_layer.update()


def solve_hand(side, want):
    """把 c_hand_ik.<side> 挪到让 hand.<side> 的世界坐标 ≈ want（迭代求解）。"""
    ctrl = rig.pose.bones.get("c_hand_ik." + side)
    hand = rig.pose.bones.get("hand." + side)
    if ctrl is None or hand is None:
        return False
    for _ in range(8):
        upd()
        cur = rig.matrix_world @ hand.head
        delta = want - cur
        if delta.length < 0.004:
            return True
        ctrl.matrix = Matrix.Translation(delta * 0.85) @ ctrl.matrix
    upd()
    return True


def hand_world(side):
    upd()
    return (rig.matrix_world @ rig.pose.bones["hand." + side].head).copy()


rest = {s: hand_world(s) for s in ("l", "r")}
print("=== rest hands ===", {k: tuple(round(v, 3) for v in p) for k, p in rest.items()})

# ── 1) 基础姿势：双手放到胯高，往身体内侧收一点 ──
for side in ("l", "r"):
    want = rest[side].copy()
    want.z -= HAND_DROP_Z
    want.x -= HAND_PULL_X * (1.0 if rest[side].x > 0 else -1.0)
    ok = solve_hand(side, want)
    got = hand_world(side)
    print("=== 手 %s 目标 (%.3f,%.3f,%.3f) 实际 (%.3f,%.3f,%.3f) %s"
          % (side, want.x, want.y, want.z, got.x, got.y, got.z, "OK" if ok else "FAIL"))

# 记录摆好之后的基准值
base_loc = {}
for side in ("l", "r"):
    pb = rig.pose.bones.get("c_hand_ik." + side)
    if pb:
        pb.rotation_mode = 'QUATERNION'
        base_loc["c_hand_ik." + side] = pb.location.copy()

# ── 2) 待机关键帧 ──
rig.animation_data_create()
action = bpy.data.actions.new("Idle")
rig.animation_data.action = action
action.use_fake_user = True

sway = {
    "c_spine_02.x": (Vector((1, 0, 0)), 1.4),
    "c_spine_03.x": (Vector((1, 0, 0)), 0.7),
    "c_head.x": (Vector((0, 1, 0)), 1.8),
}
base_q = {}
for name in sway:
    pb = rig.pose.bones.get(name)
    if pb:
        pb.rotation_mode = 'QUATERNION'
        base_q[name] = pb.rotation_quaternion.copy()

KEYS = [(1, 0.0), (13, 1.0), (25, 0.0), (37, -1.0), (49, 0.0)]   # (帧, 归一化呼吸相位)

for frame, ph in KEYS:
    scene.frame_set(frame)
    # 脊柱/头：正弦式摆动
    for name, (axis, deg) in sway.items():
        pb = rig.pose.bones.get(name)
        if pb is None:
            continue
        pb.rotation_quaternion = base_q[name] @ Quaternion(axis, math.radians(deg * ph))
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    # 双手：随呼吸上下起伏 1 cm（IK 目标也跟着动）
    for side in ("l", "r"):
        pb = rig.pose.bones.get("c_hand_ik." + side)
        if pb is None:
            continue
        pb.location = base_loc["c_hand_ik." + side] + Vector((0, 0, 0.01 * ph))
        pb.keyframe_insert("location", frame=frame)

scene.frame_start = 1
scene.frame_end = FRAMES + 1
scene.frame_set(1)

# ── 3) 导出（只留角色 + 只留 Idle）──
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
