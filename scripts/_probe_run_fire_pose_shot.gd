extends SceneTree
## 探针：**跑打开火时躯干该不该被叠加层改掉** —— 冻结相位下的四档对照。
##
## 背景（用户报「跑打确实腿动了但是感觉身体倾斜了好多」）：
##   `_probe_fire_lean.gd` 量出 `Bip001 Spine1`（胸椎）的「上」轴：
##     · 跑步（`Move_Ing`）= (0.70, −0.71, −0.11)
##     · 跑+开火（现状）= (0.95, +0.32, −0.04)   ← **差约 64°**
##   叠加层把「跑步的前倾躯干」整个换成了「站桩开火的坐姿上身」。
##
## ⚠️ 第一版本探针是「真跑起来再抓拍」，结果四档的**跑步相位各不相同**
##    （`Move_Ing` 一个循环 0.667 s，抓拍时刻差 0.1 s 就是半个姿势），
##    图看着像四档姿势不一样，其实是在比四个不同相位 —— 不可信。
##    现在改成：**冻住玩家脚本 + `speed_scale = 0`**，把
##    基础层定在 `Move_Ing` 的 0.30 s、叠加层定在 `Normal_Attack_Ing` 的 0.40 s，
##    四档看的是**同一帧**。
##
## 候选叠法（都保留手臂 / 手 / 枪，只改「额外滤掉哪些骨」）：
##   base          不开火（对照，只有 Move_Ing）
##   1_cur         只滤下半身（现状）
##   2_trunk       再滤 spine / chest
##   3_trunk_neck  再滤 spine / chest / neck / head
##
## 用法：godot --path <工程> --script res://scripts/_probe_run_fire_pose_shot.gd -- --splat=off
## 输出：`_arisu_captures/_runfirepose/*.png` + 每档的躯干轴 / 手 / 脚读数

const OUT_SUB := "_runfirepose"
const START := Vector3(0, 0.05, 12)
const BASE_T := 0.30      ## 基础层（Move_Ing）冻在哪个相位
const FIRE_T := 0.40      ## 叠加层（Normal_Attack_Ing）冻在哪个相位
const BONES := ["Bip001 Spine1", "Bip001 Neck", "Bip001 R Hand", "Bip001 L Foot"]

var _cam: Camera3D
var _out: String
var _p: Player
var _anim: AnimDriver


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	# 同伴会跑到镜头前挡人：整只藏掉
	for ch in game.get_children():
		if ch is Companion:
			(ch as Node3D).visible = false
	_p = game.get_node_or_null("Player") as Player
	if _p == null:
		print("!! 没有 Player")
		quit(1)
		return
	_anim = _p.anim as AnimDriver
	_freeze()

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	var cases := [
		{"n": "base", "extra": [], "fire": false},
		{"n": "1_cur", "extra": [], "fire": true},
		{"n": "2_trunk", "extra": ["spine", "chest"], "fire": true},
		{"n": "3_trunk_neck", "extra": ["spine", "chest", "neck", "head"], "fire": true},
	]
	for c in cases:
		print("\n=== %s（额外滤掉 %s）===" % [c["n"], str(c["extra"])])
		if c["fire"]:
			_build_overlay(c["extra"])
		else:
			_remove_overlay()
		await _pose(c["fire"])
		_report(c["n"])
		await _shot_side(c["n"])
		await _shot_back(c["n"])
	print("\n出图目录：%s" % _out)
	quit(0)


## 冻住玩家：位置、朝向、动画都不许自己动（否则四档的跑步相位对不齐）。
func _freeze() -> void:
	_p.set_physics_process(false)
	_p.set_process_input(false)
	_p.velocity = Vector3.ZERO
	_p.global_position = START
	_p._yaw = 0.0
	_p._facing_yaw = PI
	_p.model_root.rotation.y = PI
	_anim.state = AnimDriver.State.LOCOMOTION
	_anim._auto_return = false


## 把基础层定在 `Move_Ing` 的固定相位，叠加层定在开火动作的固定相位。
## `speed_scale = 0` ⇒ 不推进但**每帧照写姿态**，正是运行时那套写法（优先级更高者赢）。
func _pose(fire: bool) -> void:
	_anim.player.speed_scale = 0.0
	_anim.player.play("Move_Ing", -1.0, 1.0)
	_anim.player.seek(BASE_T, true)
	if fire and _anim.upper != null:
		_anim.upper.speed_scale = 0.0
		_anim.upper.play("Normal_Attack_Ing", -1.0, 1.0)
		_anim.upper.seek(FIRE_T, true)
	await _wait(3)


func _report(name: String) -> void:
	var sk := _anim.skeleton
	var parts: Array = []
	for bn in BONES:
		var i := sk.find_bone(bn)
		if i < 0:
			continue
		var pose := sk.get_bone_global_pose(i)
		if bn.contains("Hand") or bn.contains("Foot"):
			parts.append("%s %s" % [bn.get_slice(" ", 1), str(pose.origin.snappedf(0.01))])
		else:
			parts.append("%s 上轴 %s" % [bn.get_slice(" ", 1),
				str(pose.basis.y.normalized().snappedf(0.01))])
	print("  %s" % "   ".join(parts))


## 按 `extra` 关键词重建叠加层（复刻 `anim_driver._setup_upper_layer()`，只多一个过滤集）。
func _build_overlay(extra: Array) -> void:
	_remove_overlay()
	var ov := AnimationPlayer.new()
	ov.name = "ProbeUpper"
	ov.root_node = _anim.player.root_node
	ov.process_priority = _anim.player.process_priority + 1
	var lib := AnimationLibrary.new()
	var removed := 0
	for clip in ["Normal_Attack_Ing", "Normal_Reload"]:
		if not _anim.player.has_animation(clip):
			continue
		var a: Animation = _anim.player.get_animation(clip).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			var bone := String(a.track_get_path(t))
			bone = bone.substr(bone.rfind(":") + 1).to_lower()
			if _hit(bone, AnimDriver.LOWER_KEYWORDS) or _hit(bone, extra):
				a.remove_track(t)
				removed += 1
		lib.add_animation(clip, a)
	ov.add_animation_library(&"", lib)
	_anim.player.get_parent().add_child(ov)
	ov.animation_finished.connect(_anim._on_finished)
	# 借「静止层」这个槽放探针的变体，并把移动层摘掉 —— 让 `active_upper_layer()`
	# 一定返回探针这一层（`_speed` 被冻住时也一样）。探针跑完就退出，不用还原。
	_anim.upper = ov
	_anim.upper_move = null
	print("  叠加层：开火 %d 条轨道（两个动作共滤掉 %d 条）"
		% [ov.get_animation("Normal_Attack_Ing").get_track_count(), removed])


func _remove_overlay() -> void:
	if _anim.upper == null:
		return
	_anim.stop_upper_layer()
	var host := _anim.upper.get_parent()
	if host != null:
		host.remove_child(_anim.upper)
	_anim.upper.queue_free()
	_anim.upper = null


func _hit(bone: String, kws: Array) -> bool:
	for k in kws:
		if bone.contains(String(k).to_lower()):
			return true
	return false


func _shot_side(name: String) -> void:
	var p := _p.global_position
	_cam.fov = 32.0
	_cam.global_position = p + Vector3(3.6, 1.30, 0.0)
	_cam.look_at(p + Vector3(0.0, 0.95, 0.0), Vector3.UP)
	await _wait(3)
	root.get_texture().get_image().save_png(_out.path_join(name + "_side.png"))
	print("  出图 %s_side" % name)


func _shot_back(name: String) -> void:
	var p := _p.global_position
	_cam.fov = 36.0
	_cam.global_position = p + Vector3(0.0, 1.60, 3.4)
	_cam.look_at(p + Vector3(0.0, 0.90, 0.0), Vector3.UP)
	await _wait(3)
	root.get_texture().get_image().save_png(_out.path_join(name + "_back.png"))
	print("  出图 %s_back" % name)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
