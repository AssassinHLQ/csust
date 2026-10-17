extends Node3D
## 「老师」NPC：站在学生身后，不参战、不说话，只是**会呼吸**。
##
## ── 为什么没有 `AnimationPlayer` 的活干 ──
## 这份素材（`sensei.blend`，MMD/PMX 导出）**只有骨架、没有动作**：
## `bpy.data.actions` 是 0 条，307 个刚体、一堆物理关节，但一条关键帧都没有。
## 所以「应该是有骨骼动画的」在文件里不成立 —— 能用的只有 313 根骨。
## 与其让他像块木板，这里用两根骨（上半身 / 头）做**程序化待机**：
## 缓慢的起伏 + 极轻微的左右重心移动，周期 5 秒，幅度 1.5°，肉眼只当「在呼吸」。
##
## ⚠️ 只能写 `set_bone_pose_rotation()`：没有 `AnimationPlayer` 在抢，
##    所以不需要像 `AnimDriver` 那样搞叠加层。
##
## 模型本身 `models/npc/sensei.glb` **不随仓库分发**（.gitignore），
## 克隆者只看到一行 warning，游戏照常跑。

## 模型路径。换人不改场景，改这个导出值就行。
@export var model_path := "res://models/npc/sensei.glb"
## 朝向：MMD 素材在 Godot 里**脸朝节点的 +Z**（实测：0° 时从 −Z 侧拍到的是后脑勺），
## 所以要 180° 才和同伴一样朝 −Z。这一条是渲图 `_probe_sensei_shot.gd` 看出来的。
@export var facing_yaw_deg := 180.0
## 手臂下垂角度（度）。素材是**T-pose**（两臂平举），不放下来会像个衣架。
## 左右两侧要反向转（各绕骨架 Z 轴），见 `_relax_arms()`。
@export var arm_down_deg := 55.0
@export var elbow_deg := 8.0
## 呼吸幅度（度）与频率（次/秒）
@export var breath_deg := 1.5
@export var breath_hz := 0.2
## 整体缩放。模型自带 1.57 m 身高，正常不用动
@export var model_scale := 1.0

var _skel: Skeleton3D
var _chest := -1
var _head := -1
var _chest_rest := Quaternion.IDENTITY
var _head_rest := Quaternion.IDENTITY
## 手臂的「放下」姿势（骨索引 → 四元数），`_process` 的呼吸要基于它叠加
var _arm_rest := {}
var _t := 0.0


func _ready() -> void:
	rotation.y = deg_to_rad(facing_yaw_deg)
	if not ResourceLoader.exists(model_path):
		push_warning("[Sensei] 找不到模型：%s（老师不出现，游戏继续）" % model_path)
		return
	var ps := load(model_path) as PackedScene
	if ps == null:
		push_warning("[Sensei] %s 不是 PackedScene" % model_path)
		return
	var inst := ps.instantiate() as Node3D
	if inst == null:
		push_warning("[Sensei] %s 实例化失败" % model_path)
		return
	inst.scale = Vector3.ONE * model_scale
	add_child(inst)
	_skel = _find_skel(inst)
	if _skel == null:
		push_warning("[Sensei] 模型里没有 Skeleton3D，只做静态摆放")
		return
	# MMD 骨名是日文：上半身 / 上半身2 / 頭。找不到就算了，不该因此报错。
	_chest = _bone(_skel, ["上半身", "上半身2", "Bip001 Spine1"])
	_head = _bone(_skel, ["頭", "Bip001 Head"])
	if _chest >= 0:
		_chest_rest = _skel.get_bone_pose_rotation(_chest)
	if _head >= 0:
		_head_rest = _skel.get_bone_pose_rotation(_head)
	_relax_arms()


## 把 T-pose 的平举手臂放下来。
##
## ── 为什么是绕骨架 Z 轴、左右反向 ──
## T-pose 里两臂分别指向骨架 **+X** 和 **−X**，要「往下」就是绕 Z 转：
## `(1,0,0)` 绕 +Z 转 −θ 得到 `(cosθ, −sinθ, 0)`（往下）；右臂 `(−1,0,0)` 反而要 +θ。
## 夹到骨局部空间用的是**父骨**的 global rest 基（同 `pose_fix.gd` 那条教训：
## `AnimationPlayer` 的姿势是左乘在父空间的）。
func _relax_arms() -> void:
	_arm_rest.clear()
	var pairs := [
		["左腕", -1.0],
		["右腕", 1.0],
	]
	for p in pairs:
		var idx := _skel.find_bone(String(p[0]))
		if idx < 0:
			continue
		var sign_f: float = float(p[1])
		var q := _delta(idx, Vector3(0.0, 0.0, 1.0), arm_down_deg * sign_f)
		_arm_rest[idx] = q
		_skel.set_bone_pose_rotation(idx, q)
	for name_value in ["左ひじ", "右ひじ"]:
		var idx := _skel.find_bone(String(name_value))
		if idx < 0:
			continue
		var sign_f := -1.0 if String(name_value).begins_with("左") else 1.0
		_skel.set_bone_pose_rotation(idx,
			_delta(idx, Vector3(0.0, 0.0, 1.0), elbow_deg * sign_f))


## 骨架空间里绕 `axis` 转 `deg`，夹到这根骨的局部空间。
func _delta(idx: int, axis: Vector3, deg: float) -> Quaternion:
	var g := Basis.IDENTITY
	var parent := _skel.get_bone_parent(idx)
	if parent >= 0:
		g = _skel.get_bone_global_rest(parent).basis.orthonormalized()
	var gq := g.get_rotation_quaternion()
	return (gq.inverse() * Quaternion(axis, deg_to_rad(deg)) * gq).normalized()


## 待机：肋骨起伏（上半身小幅俯仰）+ 头随呼吸极轻地点一下。
## 相位刻意错开 25%，两个动作不会像机械一样同时到顶。
func _process(delta: float) -> void:
	if _skel == null:
		return
	_t += delta
	var w := TAU * breath_hz * _t
	if _chest >= 0:
		_skel.set_bone_pose_rotation(_chest,
			_chest_rest * Quaternion(Vector3.RIGHT, deg_to_rad(breath_deg * sin(w))))
	if _head >= 0:
		_skel.set_bone_pose_rotation(_head,
			_head_rest * Quaternion(Vector3.RIGHT,
				deg_to_rad(breath_deg * 0.4 * sin(w * 0.75 + 0.9))))


func _bone(sk: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	return -1


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
