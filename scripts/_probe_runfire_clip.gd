extends SceneTree
## 探针（要真渲染）：看 `models/RunFire.glb` 并进来的那条 **单条跑打动作** 到底长什么样。
##
## 三个对照，同一机位、同一相位网格：
##   run_*      只播 `Move_Ing`（跑步基线）
##   clip_*     播 `RunFire_Ing`（Blender 里拼的那条，时间轴 0~2.667 s）
##   stand_*    站桩开火 `Normal_Attack_Ing`（对照「后仰」从哪来）
##
## 每张图旁边打一行数字：
##   trunk  = 世界上方向和「骨盆→头」的点积（1.0 直立，越小越往前趴）
##   barrel = 枪管朝向和角色前向的夹角（0° = 指正前方）
##   feet   = 两只脚的骨架高度（证明腿在跑）
##
## 用法（别加 --headless）：
##   godot --path <工程> --script res://scripts/_probe_runfire_clip.gd -- --splat=off
## 输出：`_arisu_captures/_runfireclip/`

const OUT_DIR := "_arisu_captures/_runfireclip"
const SIZE := Vector2i(640, 720)
const CLIP := "RunFire_Ing"

var _sk: Skeleton3D
var _ap: AnimationPlayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)
	var p := game.get_node_or_null("Player") as Player
	if p == null or p.anim == null:
		print("[clip] !! 没有 Player/AnimDriver")
		quit(1)
		return
	p.set_physics_process(false)
	var anim := p.anim as AnimDriver
	_sk = anim.skeleton
	_ap = anim.player
	print("[clip] runfire 报告：%s" % str(anim.runfire))
	if not _ap.has_animation(CLIP):
		print("[clip] !! 动作库里没有 %s —— 先跑 `_blender_arisu/seed_runfire.py -- --export`" % CLIP)
		quit(1)
		return

	var cam := Camera3D.new()
	cam.name = "ProbeCam"
	cam.fov = 40.0
	root.add_child(cam)
	# 机位按**角色自己的尺寸**算：先量一次头骨 / 脚骨，再固定下来，
	# 这样「只跑 / 跑打 / 站桩」三组之间能直接对比（固定机位，不跟人）。
	_ap.speed_scale = 0.0
	_ap.play("Normal_Idle")
	_ap.seek(0.0, true)
	await _wait(3)
	var head0 := _bone_world("Bip001 Head")
	var feet0 := (_bone_world("Bip001 L Foot") + _bone_world("Bip001 R Foot")) * 0.5
	var height := maxf(head0.y - feet0.y, 0.5)
	var center: Vector3 = (head0 + feet0) * 0.5
	var dist := height * 2.7
	cam.global_position = center + Vector3(dist, height * 0.45, 0.0)
	cam.look_at(center + Vector3(0.0, height * 0.1, 0.0), Vector3.UP)
	cam.make_current()
	print("[clip] 角色高 %.2f m，机位 %s 看向 %s" % [height,
		str(cam.global_position.snappedf(0.01)), str(center.snappedf(0.01))])

	# ---- 只跑 ----
	anim.stop_upper_layer()
	_ap.speed_scale = 0.0
	_ap.play("Move_Ing")
	var mv_len: float = _ap.get_animation("Move_Ing").length
	for i in 4:
		await _shot(cam, out.path_join("run_%d.png" % i), "Move_Ing", mv_len * 0.25 * i, "只跑")

	# ---- 单条跑打动作 ----
	# ⚠️ 采样点**不能**取 1/4 等分：这条动作是 4 个跑步周期拼起来的，
	#    每 0.667 s 一个循环，按 1/4 取正好每张都落在同一相位（量出来脚一动不动，
	#    第一版就是这么误判的）。改成 4 个互不重合的相位。
	for f in [0, 5, 10, 15]:
		await _shot(cam, out.path_join("clip_%02d.png" % f), CLIP, float(f) / 24.0, "跑打(单条)")

	# ---- 站桩开火（对照）----
	var at_len: float = _ap.get_animation("Normal_Attack_Ing").length
	for i in 3:
		await _shot(cam, out.path_join("stand_%d.png" % i), "Normal_Attack_Ing",
			at_len * (0.15 + 0.25 * i), "站桩开火")

	print("[clip] 输出目录 %s" % out)
	quit(0)


func _shot(cam: Camera3D, file: String, clip: String, t: float, tag: String) -> void:
	_ap.play(clip)
	_ap.seek(t, true)
	for _i in 5:
		await process_frame
	var m := _measure()
	print("[clip] %-10s %-18s t=%.2f  trunk=%.3f  barrel=%6.1f°  feet=%.3f/%.3f  hand=%.3f"
		% [tag, clip, t, m["trunk"], m["barrel"], m["foot_l"], m["foot_r"], m["hand_h"]])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)


func _base_pos() -> Vector3:
	var p := _sk.get_parent_node_3d()
	return p.global_position if p != null else Vector3.ZERO


func _measure() -> Dictionary:
	var pelvis := _bone_world("Bip001 Pelvis")
	var head := _bone_world("Bip001 Head")
	var trunk := Vector3.UP.dot((head - pelvis).normalized())
	# 枪管：`bone_Railgunup_01` 的 +Y 就是枪身朝向（这一套里枪系骨的朝向约定见 README）
	var barrel := 180.0
	var bi := _sk.find_bone("bone_Railgunup_01")
	if bi >= 0:
		var d: Vector3 = (_sk.global_transform.basis * _sk.get_bone_global_pose(bi).basis).y
		# 角色前向取骨架根节点的 −Z（玩家模型朝 −Z，见 player.gd）
		var fwd: Vector3 = -_sk.global_transform.basis.z
		barrel = rad_to_deg(acos(clampf(d.normalized().dot(fwd.normalized()), -1.0, 1.0)))
	var fl := _bone_world("Bip001 L Foot")
	var fr := _bone_world("Bip001 R Foot")
	var hr := _bone_world("Bip001 R Hand")
	return {
		"trunk": trunk, "barrel": barrel,
		"foot_l": fl.y, "foot_r": fr.y, "hand_h": hr.y,
	}


func _bone_world(bone: String) -> Vector3:
	var i := _sk.find_bone(bone)
	if i < 0:
		return Vector3.INF
	return _sk.global_transform * _sk.get_bone_global_pose(i).origin


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
