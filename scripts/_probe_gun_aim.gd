extends SceneTree
## 探针：**枪到底朝哪** —— 站桩开火 / 跑打开火（整身动作）各量一遍。
##
## 用户 2026-10-18：「跑打时怎枪不是朝前的」。
##
## 判据用两个点：`bone_Railgun_Muzzle_01`（枪口）− `bone_magazine`（弹匣/机匣），
## 这两个点的连线就是**枪管方向**（比拿某根骨的 +Y 猜可靠，之前那个 81° 一直是错的）。
## 再和「角色前向」（模型根节点的 −Z，`player.gd` 里也这么用）比夹角：
##   0° = 正前方；>60° = 明显打横；负俯角 = 枪口朝下。
##
## 用法（要真渲染，别加 --headless）：
##   godot --path <工程> --script res://scripts/_probe_gun_aim.gd -- --splat=off
## 输出：`_arisu_captures/_gunaim/`

const OUT_DIR := "_arisu_captures/_gunaim"
const SIZE := Vector2i(900, 700)
const FIRE_MS := 700


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)
	var p := game.get_node_or_null("Player") as Player
	if p == null or p.anim == null:
		print("[aim] !! 没有 Player/AnimDriver")
		quit(1)
		return
	var anim := p.anim as AnimDriver
	# ⚠️ 必须关掉玩家脚本：它会每帧 `set_locomotion(真实速度≈0)` 把 `_speed` 打回 0，
	#    于是 `request_fire()` 永远走「站桩」那条路（第一版就量成了 Normal_Idle，白量）。
	p.set_physics_process(false)
	# 用游戏自己的相机拍，看到的就是用户看到的
	await _wait(10)

	# ① 站桩开火
	anim.reset_state()
	anim.set_locomotion(0.0, true, 0.0)
	await _wait(10)
	anim.request_fire()
	await _wait_ms(300)
	var stand := _measure(p)
	await _shot(out.path_join("1_stand_fire.png"), "站桩开火")
	print("[aim] 站桩开火：%s" % _fmt(stand, anim))

	# ② 跑打开火（整身动作那条路）
	anim.reset_state()
	for _i in 30:
		anim.set_locomotion(6.8, true, 0.0)
		await process_frame
	anim.request_fire()
	for _i in 8:
		anim.set_locomotion(6.8, true, 0.0)
		await process_frame
	var run := _measure(p)
	await _shot(out.path_join("2_run_fire.png"), "跑打开火")
	print("[aim] 跑打开火：%s" % _fmt(run, anim))
	print("[aim] 诊断：has_runfire=%s extra=%s runfire_ok=%s" % [
		anim.has_runfire(), anim.extra_clip, str(anim.runfire.get("ok", false))])
	# 这条动作里**缺了哪些骨**：Godot 导入 glb 时会把「全程不变」的轨道删掉
	# （`animation/remove_immutable_tracks`），枪骨要是被删了就没人写它 ——
	# 枪会停在上一套动作给的姿势上，看起来就是「枪不朝前」。
	var a := anim.player.get_animation(anim.extra_clip)
	var have := {}
	for t in a.get_track_count():
		var tp := String(a.track_get_path(t))
		have[tp.substr(tp.rfind(":") + 1)] = true
	var miss: Array = []
	for b in anim.skeleton.get_bone_count():
		var nm := String(anim.skeleton.get_bone_name(b))
		if not have.has(nm):
			miss.append(nm)
	print("[aim] 动作里轨道 %d 条 / 覆盖骨 %d 根 / **缺 %d 根**：%s"
		% [a.get_track_count(), have.size(), miss.size(), str(miss)])

	print("[aim] 差值：俯仰 %+.1f°  偏航 %+.1f°（跑打 − 站桩）"
		% [run["pitch"] - stand["pitch"], run["yaw"] - stand["yaw"]])
	print("[aim] 输出目录 %s" % out)
	quit(0)


func _measure(p: Player) -> Dictionary:
	var anim := p.anim as AnimDriver
	var sk := anim.skeleton
	var muzzle := _bone_world(sk, "bone_Railgun_Muzzle_01")
	var mag := _bone_world(sk, "bone_magazine")
	var d := (muzzle - mag).normalized()
	var fwd: Vector3 = -p.model_root.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var flat := Vector3(d.x, 0.0, d.z).normalized()
	return {
		"pitch": rad_to_deg(asin(clampf(d.y, -1.0, 1.0))),        # 正 = 朝上
		"yaw": rad_to_deg(acos(clampf(flat.dot(fwd), -1.0, 1.0))), # 0 = 正前方
		"dir": d, "fwd": fwd,
	}


func _fmt(m: Dictionary, anim: AnimDriver) -> String:
	return "枪管方向 %s  前向 %s  俯仰 %+.1f°  偏航 %.1f°  基础层 %s 叠加层 %s 状态 %s" % [
		str((m["dir"] as Vector3).snappedf(0.01)), str((m["fwd"] as Vector3).snappedf(0.01)),
		m["pitch"], m["yaw"], anim.player.current_animation,
		"无" if anim.upper_clip() == "" else anim.upper_clip(), anim.current_state_name()]


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	if i < 0:
		return Vector3.INF
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _shot(file: String, tag: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("[aim]   [img] %s（%s）" % [file, tag])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
