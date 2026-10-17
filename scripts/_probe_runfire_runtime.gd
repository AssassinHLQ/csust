extends SceneTree
## 探针：**运行时**跑打开火用的是哪一层，那一层到底滤没滤。
##
## 背景：数据层已经量过（`_probe_fire_vs_run_bones.gd`）：
##   `Move_Ing` 与 `Normal_Attack_Ing` 的逐骨差里，躯干（Spine1 +60.9° 等）都在
##   `TRUNK_KEYWORDS` 覆盖范围内，**没被覆盖的只有 7 根**（枪/手指/头发/挂饰）。
##   所以如果运行时还是后倾，只可能是「移动层没有被用上」或「移动层没滤干净」。
##
## 本探针直接读运行时的两层：
##   · `active_upper_layer()` 返回的是哪一层；
##   · 两层的 `Normal_Attack_Ing` 各有多少条轨道（滤过的必然更少）；
##   · 开火瞬间 `Bip001 Spine1` 的「上」轴，和只跑时对比。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_runfire_runtime.gd

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 让 game.tscn 不加载泼溅，省得吃显存/时间
	if not OS.get_cmdline_user_args().has("--splat=off"):
		print("[rt] 提示：建议带 --splat=off 跑")
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(12)

	var p := game.get_node_or_null("Player")
	if p == null:
		print("!! 没有 Player")
		quit(1)
		return
	var anim = p.get("anim")
	if anim == null:
		print("!! Player 上没有 anim")
		quit(1)
		return

	var upper = anim.get("upper")
	var upper_move = anim.get("upper_move")
	print("[rt] upper=%s  upper_move=%s" % [
		"—" if upper == null else String(upper.name),
		"—" if upper_move == null else String(upper_move.name)])
	for l in [upper, upper_move]:
		if l == null:
			continue
		var a = l.get_animation("Normal_Attack_Ing") if l.has_animation("Normal_Attack_Ing") else null
		print("   %-14s 在树里=%s  攻击轨道=%d" % [
			String(l.name), str(l.is_inside_tree()),
			-1 if a == null else a.get_track_count()])
	var full = anim.get("player").get_animation("Normal_Attack_Ing")
	print("   原始 Normal_Attack_Ing 轨道=%d" % full.get_track_count())
	print("   移动层滤掉躯干轨道=%d 条（anim_driver 记账）" % int(anim.get("trunk_tracks_removed")))

	# ⚠️ 必须关掉玩家的物理：`player.gd` 每帧都会用**真实速度**调
	#    `set_locomotion()`，站着不动时它把 `_speed` 按回 0 —— 那测的就是「站桩开火」，
	#    不是「跑打」。关掉之后本探针自己每帧喂 6.8 m/s。
	p.set_physics_process(false)
	anim.call("set_locomotion", 6.8, true, 0.0)
	await _wait(6)
	var run_pitch := _spine_pitch(anim)
	print("\n[rt] 只跑：Spine1 上轴 %s" % str(run_pitch.snappedf(0.01)))

	# 跑 + 开火（每帧重新喂速度，和真实跑动时同一个值）
	anim.call("set_locomotion", 6.8, true, 0.0)
	anim.call("request_fire")
	await _wait(3)
	var layer = anim.call("active_upper_layer")
	print("[rt] 开火后 active_upper_layer = %s" % ("null" if layer == null else String(layer.name)))
	anim.call("set_locomotion", 6.8, true, 0.0)
	await _wait(6)
	var fire_pitch := _spine_pitch(anim)
	print("[rt] 跑+开火：Spine1 上轴 %s" % str(fire_pitch.snappedf(0.01)))
	print("[rt] 角度差 %.1f°（**该接近 0**；接近 60° 就说明躯干没滤）" % rad_to_deg(
		run_pitch.angle_to(fire_pitch)))
	quit(0)


func _spine_pitch(anim) -> Vector3:
	var sk: Skeleton3D = anim.get("skeleton")
	var i := sk.find_bone("Bip001 Spine1")
	if i < 0:
		for b in sk.get_bone_count():
			if String(sk.get_bone_name(b)).to_lower().contains("spine1"):
				i = b
				break
	if i < 0:
		return Vector3.ZERO
	return sk.get_bone_global_pose(i).basis.y.normalized()


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
