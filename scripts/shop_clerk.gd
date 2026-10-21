class_name ShopClerk
extends Node3D
## 天使24 的店员：**小空（Sora）**。
##
## ── 素材来源（署名，务必保留）──
##   模型：`小空1donzuo.blend`　作者：**薛定谔的小问号**（2023-12，用户 2026-10-21 提供）
##   转换：Blender 5.0 无头导出 → `models/npc/sora/sora.glb`
##   ⚠️ 第三方素材，只在本地学习用；`/models/npc/**` 在 `.gitignore` 里，不随仓库分发。
##
## ── 为什么不做「摆姿势」──
## 原模型是 A-pose（双臂张开约 45°），本来想用 `set_bone_pose_rotation()` 把上臂转下来，
## 但实测**转不动**：这套 Maya rig 导成 glTF 之后，`hand.l` 的父链是
## `hand.l → forearm.l → c_traj → c_pos` —— 变形骨之间**不是链式父子关系**
## （原工程靠约束/IK 驱动，glTF 没有约束），改一根骨的姿态只会影响它自己的子树，
## 掰出来是断的。见 `_probe_sora_axis.gd` 的量法（用手骨世界 y 判，别用蒙皮 AABB，
## 蒙皮网格的 `get_aabb()` 是绑定姿态的）。
##
## 好在**不需要**摆：她的手骨世界高度 ≈ 0.89 m / 0.69 m，柜台台面是 **1.04 m** ——
## A-pose 的双手整整齐齐藏在柜台后面，玩家只看得到头肩。真要让她站到空地上，
## 得回 Blender 做一个真正的待机动画再导进来。

const MODEL := "res://models/npc/sora/sora.glb"
## 待机摆动（整只模型左右轻晃，幅度很小，不动骨架）
@export var idle_sway := true
@export var sway_deg := 1.1
@export var sway_hz := 0.16

var model: Node3D
var skeleton: Skeleton3D
var bone_count := 0
## 量出来的：两只手骨的世界高度（自检/探针用来对照台面高度）
var hand_y := {}

var _t := 0.0
var _idle: AnimationPlayer


func _ready() -> void:
	if not ResourceLoader.exists(MODEL):
		push_warning("[Clerk] 没有小空的模型：%s（先把 .blend 用 Blender 转成 glb）" % MODEL)
		return
	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_error("[Clerk] %s 不是有效的场景" % MODEL)
		return
	model = ps.instantiate() as Node3D
	add_child(model)
	skeleton = _best_skeleton(model)
	if skeleton != null:
		bone_count = skeleton.get_bone_count()
		for side in ["l", "r"]:
			var idx := _find_bone("hand." + side)
			if idx >= 0:
				hand_y[side] = (skeleton.global_transform
					* skeleton.get_bone_global_pose(idx).origin).y
	_play_idle()
	print("[Clerk] 小空就位：%s（骨架 %d 骨，手骨高度 L=%.2f R=%.2f m，动画 %s）" % [
		MODEL.get_file(), bone_count,
		float(hand_y.get("l", -1.0)), float(hand_y.get("r", -1.0)),
		"Idle" if _idle != null else "无（保持静止姿势）"])


## 播放 GLB 里烘焙好的待机动画（`tools/make_sora_idle.py` 用 Blender 做的）。
## 有动画就不再程序化晃 model —— 两套一起动会互相打架。
func _play_idle() -> void:
	for n in model.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap.get_animation_list().has("Idle"):
			ap.play("Idle")
			ap.speed_scale = 1.0
			_idle = ap
			return


func _process(delta: float) -> void:
	if _idle != null or not idle_sway or model == null:
		return
	_t += delta
	model.rotation.y = deg_to_rad(sway_deg) * sin(_t * TAU * sway_hz)


func _find_bone(want: String) -> int:
	if skeleton == null:
		return -1
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i) == want:
			return i
	return -1


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _skeletons(node):
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _skeletons(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is Skeleton3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_skeletons(c))
	return out
