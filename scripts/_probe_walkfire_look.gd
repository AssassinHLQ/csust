extends SceneTree
## 探针（要真渲染）：**白天、平台上**看「走打 / 跑打」到底长什么样，
## 并量三件事：
##   ① 弹道起点（`Weapon/Muzzle` 标记 = 曳光弹与枪口火光的起点）离**视觉枪口**
##      （`bone_Railgun_Muzzle_0x`）有多远 —— 用户：「跑打子弹发射的点不在枪口上，偏右了」
##   ② 枪管有没有**侧倾**（枪的「上」方向与世界竖直的夹角）
##   ③ 躯干有没有**右倾**（胸椎 up 轴在角色右方向上的分量）—— 用户：「走打还是很奇怪，右倾了一点」
##
## 用法（要真渲染；`--splat=off` 省显存）：
##   godot --path <工程> --script res://scripts/_probe_walkfire_look.gd -- --splat=off
## 输出：`_arisu_captures/_walklook/`

const OUT_DIR := "_arisu_captures/_walklook"
const SIZE := Vector2i(1100, 720)
## 拉到平台上（晒得到太阳），别在画室609 里拍 —— 里面太暗，什么都看不清
const SPOT := Vector3(-14.0, 0.1, -12.0)


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
		print("[look] !! 没有 Player/AnimDriver")
		quit(1)
		return
	var anim := p.anim as AnimDriver
	var wpn := game.get_node_or_null("Player/Weapon") as Weapon
	p.set_physics_process(false)
	p.global_position = SPOT
	await _wait(4)

	for c in [["1_walk_fire", 2.4], ["2_run_fire", 6.8]]:
		var tag := String(c[0])
		var spd := float(c[1])
		anim.reset_state()
		anim.set_locomotion(0.0, true, 0.0)
		await _wait(6)
		for _i in 20:
			anim.set_locomotion(spd, true, 0.0)
			await process_frame
		anim.request_fire()
		for _i in 20:
			anim.set_locomotion(spd, true, 0.0)
			await process_frame
		print("[look] %s：%s" % [tag, _fmt(p, anim, wpn)])
		# 用户视角
		await _shot(out.path_join("%s_cam.png" % tag))
		# 侧面 / 背后俯视（另开一台相机，看枪和身体的相对关系）
		await _side_shots(p, out, tag)

	print("[look] 输出目录 %s" % out)
	quit(0)


func _fmt(p: Player, anim: AnimDriver, wpn: Weapon) -> String:
	var sk := anim.skeleton
	var wb := sk.find_bone(AnimDriver.GUN_BONE)
	var gun_up := Vector3.UP
	if wb >= 0:
		gun_up = ((sk.global_transform * sk.get_bone_global_pose(wb)).basis * Vector3.UP).normalized()
	var spine_up: Vector3 = anim.bone_up_axis("Bip001 Spine1")
	var right: Vector3 = p.model_root.global_transform.basis.x.normalized()
	var roll_trunk := rad_to_deg(asin(clampf(spine_up.dot(right), -1.0, 1.0)))
	var cant := rad_to_deg(acos(clampf(gun_up.dot(Vector3.UP), -1.0, 1.0)))
	return ("弹道起点离枪口 %.2f m（标记 %s / 骨 %s）  枪管侧倾 %.0f°  "
		+ "躯干右倾 %+.1f°  speed_scale %.2f  基础层 %s") % [
		_muzzle_gap(p, anim, wpn),
		str(wpn.muzzle.global_position.snappedf(0.01)) if wpn != null else "-",
		str(_bone_muzzle(p, anim).snappedf(0.01)),
		cant, roll_trunk, anim.player.speed_scale, anim.current_clip()]


func _bone_muzzle(p: Player, anim: AnimDriver) -> Vector3:
	var sk := anim.skeleton
	for b in ["bone_Railgun_Muzzle_03", "bone_Railgun_Muzzle_01"]:
		var i := sk.find_bone(b)
		if i >= 0:
			return sk.global_transform * sk.get_bone_global_pose(i).origin
	return Vector3.INF


func _muzzle_gap(p: Player, anim: AnimDriver, wpn: Weapon) -> float:
	if wpn == null:
		return -1.0
	return wpn.muzzle.global_position.distance_to(_bone_muzzle(p, anim))


func _side_shots(p: Player, out: String, tag: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()
	var eye: Vector3 = p.global_position + Vector3(0.0, 1.15, 0.0)
	var fwd: Vector3 = p.model_root.global_transform.basis.z.normalized()
	var right: Vector3 = p.model_root.global_transform.basis.x.normalized()
	var shots := [
		["side", eye + right * 2.4],
		["back", eye - fwd * 2.2 + Vector3.UP * 1.4],
	]
	for sh in shots:
		cam.global_position = sh[1]
		cam.look_at(eye, Vector3.UP)
		await _shot(out.path_join("%s_%s.png" % [tag, String(sh[0])]))
	cam.queue_free()


func _shot(file: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("[look]   [img] %s" % file)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
