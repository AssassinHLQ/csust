extends SceneTree
## 探针：**枪有没有对准准星** —— 四种状态各量一遍，并各拍一张用户视角的图。
##
## 用户 2026-10-18：「跑打攻击时武器还是歪着的，没对齐准星；走路攻击时改一下，
## 把走路改成慢速的跑动画，这样子走打就有枪了」。
##
## 量三样东西：
##   ① 枪管方向 = `bone_Railgun_Muzzle_01` − `bone_magazine`（见 `_probe_gun_aim.gd`）
##      → 分别和**相机前向**（准星）× **角色前向**（模型 −Z）比夹角
##   ② 武器骨的**世界缩放**：素材 `Cafe_Walk` 把 `Bip001_Weapon` 缩到 ≈0，
##      量这个就知道「枪到底在不在」
##   ③ 武器网格的世界包围盒尺寸（同上，但量的是真渲染的东西）
##
## 用法（要真渲染；`--splat=off` 省显存）：
##   godot --path <工程> --script res://scripts/_probe_aim_cross.gd -- --splat=off
## 输出：`_arisu_captures/_aimcross/`

const OUT_DIR := "_arisu_captures/_aimcross"
const SIZE := Vector2i(1000, 700)


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
		print("[cross] !! 没有 Player/AnimDriver")
		quit(1)
		return
	var anim := p.anim as AnimDriver
	var cam := game.get_node_or_null("Player/CameraRig/SpringArm3D/Camera3D") as Camera3D
	# ⚠️ 关掉玩家脚本：它会每帧 `set_locomotion(真实速度≈0)` 把 `_speed` 打回 0
	p.set_physics_process(false)
	await _wait(10)

	# 枪骨的父链（掰枪的旋转要换算到父骨坐标系，得知道它挂在哪）
	var sk0 := (p.anim as AnimDriver).skeleton
	for b in ["Bip001_Weapon", "bone_magazine", "bone_Railgun_Muzzle_01"]:
		var i := sk0.find_bone(b)
		var chain: Array[String] = []
		var c := i
		while c >= 0:
			chain.append(String(sk0.get_bone_name(c)))
			c = sk0.get_bone_parent(c)
		print("[cross] 骨 %-26s 父链：%s" % [b, " ← ".join(chain)])

	var cases := [
		["1_run（只跑）", 6.8, false],
		["2_run_fire（跑打）", 6.8, true],
		["3_walk（只走）", 2.4, false],
		["4_walk_fire（走打）", 2.4, true],
	]
	for c in cases:
		var tag := String(c[0])
		var spd := float(c[1])
		anim.reset_state()
		anim.set_locomotion(0.0, true, 0.0)
		await _wait(6)
		for _i in 24:
			anim.set_locomotion(spd, true, 0.0)
			await process_frame
		if bool(c[2]):
			anim.request_fire()
			for _i in 10:
				anim.set_locomotion(spd, true, 0.0)
				await process_frame
		var m := _measure(p, cam)
		print("[cross] %-18s %s" % [tag, _fmt(m, anim)])
		await _shot(out.path_join("%s.png" % tag.split("（")[0]))

	# 侧面 + 3/4 侧：查「枪掰正之后还在不在手里」（只掰枪骨，手没动过）
	var cam2 := Camera3D.new()
	cam2.fov = 55.0
	cam2.far = 200.0
	root.add_child(cam2)
	cam2.make_current()
	anim.reset_state()
	anim.set_locomotion(6.8, true, 0.0)
	await _wait(10)
	anim.request_fire()
	for _i in 20:
		anim.set_locomotion(6.8, true, 0.0)
		await process_frame
	var eye: Vector3 = p.global_position + Vector3(0.0, 1.1, 0.0)
	var fwd: Vector3 = p.model_root.global_transform.basis.z
	var right: Vector3 = p.model_root.global_transform.basis.x
	var shots := [
		["side_right", eye + right.normalized() * 2.6],
		["side_left", eye - right.normalized() * 2.6],
		["front34", eye + fwd.normalized() * 2.2 + right.normalized() * 1.6],
	]
	for sh in shots:
		cam2.global_position = sh[1]
		cam2.look_at(eye, Vector3.UP)
		await _shot(out.path_join("5_%s.png" % String(sh[0])))

	print("[cross] 输出目录 %s" % out)
	quit(0)


func _measure(p: Player, cam: Camera3D) -> Dictionary:
	var anim := p.anim as AnimDriver
	var sk := anim.skeleton
	var d := (_bone_world(sk, "bone_Railgun_Muzzle_01") - _bone_world(sk, "bone_magazine")).normalized()
	var fwd: Vector3 = -p.model_root.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	var cam_flat := Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	var flat := Vector3(d.x, 0.0, d.z).normalized()
	# 武器骨的世界缩放 + 武器网格的世界包围盒
	var wb := sk.find_bone("Bip001_Weapon")
	var wscale := 0.0
	var wbox := Vector3.ZERO
	if wb >= 0:
		wscale = (sk.global_transform * sk.get_bone_global_pose(wb)).basis.get_scale().length() / sqrt(3.0)
	for n in p.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).contains("Weapon") and not String(mi.name).begins_with("FX"):
			wbox = (mi.global_transform * mi.get_aabb()).size
			break
	var skx: Vector3 = sk.global_transform.basis * Vector3.RIGHT
	var skx_flat := Vector3(skx.x, 0.0, skx.z).normalized()
	var bodyz: Vector3 = p.model_root.global_transform.basis.z
	var body_flat := Vector3(bodyz.x, 0.0, bodyz.z).normalized()
	return {
		"pitch": rad_to_deg(asin(clampf(d.y, -1.0, 1.0))),
		"yaw_body": rad_to_deg(acos(clampf(flat.dot(fwd), -1.0, 1.0))),
		"yaw_cam": rad_to_deg(acos(clampf(flat.dot(cam_flat), -1.0, 1.0))),
		"cam_vs_body": rad_to_deg(acos(clampf(cam_flat.dot(fwd), -1.0, 1.0))),
		"wscale": wscale, "wbox": wbox,
		"dir": d,
		# 骨架 +X 在世界里朝哪：Blender 那边认定「角色前方 = 骨架 +X」
		"skx_vs_cam": rad_to_deg(acos(clampf(skx_flat.dot(cam_flat), -1.0, 1.0))),
		"skx_dot_gun": rad_to_deg(acos(clampf(absf(skx_flat.dot(flat)), -1.0, 1.0))),
		# 模型根节点的 +Z 在世界里朝哪（= 之前一直当成「角色前向」的那个）
		"bodyz_vs_cam": rad_to_deg(acos(clampf(body_flat.dot(cam_flat), -1.0, 1.0))),
	}


func _fmt(m: Dictionary, anim: AnimDriver) -> String:
	return ("枪 %s 俯仰 %+.0f°  偏航(准星) %.0f°  偏航(模型−Z) %.0f°  "
		+ "骨架+X 距准星 %.0f° / 距枪 %.0f°  模型+Z 距准星 %.0f°  "
		+ "武器骨缩放 %.2f  枪盒 %s  基础层 %s  叠加层 %s  %s
"
		+ "                        掰枪：差 %.0f° → 实际掰 %.0f°") % [
		str((m["dir"] as Vector3).snappedf(0.01)),
		m["pitch"], m["yaw_cam"], m["yaw_body"],
		m["skx_vs_cam"], m["skx_dot_gun"], m["bodyz_vs_cam"],
		m["wscale"], str((m["wbox"] as Vector3).snappedf(0.01)),
		anim.player.current_animation,
		"无" if anim.upper_clip() == "" else anim.upper_clip(),
		anim.current_state_name(),
		anim.gun_aim_deg, anim.gun_aim_applied_deg]


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	if i < 0:
		return Vector3.INF
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _shot(file: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("[cross]   [img] %s" % file)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
