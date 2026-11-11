extends SceneTree
## 出图：把「光弹实际飞的线」和「相机瞄准射线」画在一起，检查还有没有「锐角拐弯」。
##
## 用户 2026-11-11：「这个子弹对齐了准星，但是看起来是枪打出的子弹**锐角拐弯**」。
##
## 画三样东西：
##   · **红色**细杆 = 旧路径（真实枪口 → 命中点）。这就是用户看到的拐弯。
##   · **绿色**细杆 = 新路径（射线上、与枪口同进深 → 命中点）。应当与准星方向重合。
##   · **黄色**小球 = 枪口骨位置；**青色**小球 = 新的视觉起点。
##
##   _tools/run_shot.sh res://scripts/_probe_bolt_kink.gd -- --no-capture --splat=off
## 输出 `_arisu_captures/_bolt_kink.png`
##
## ⚠️ 用 `--splat=off`（省 14 分钟加载）。它同时会关掉 609 的碰撞，所以这里
##    把 `range_meters` 压到 6 m：即使没打到东西，弹道也止在 6 m 处，图照样能看。

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_NAME := "_bolt_kink.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1600, 900))
	for _i in 3:
		await process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame

	var player := game.get_node_or_null("Player") as Node3D
	var weapon := game.get_node_or_null("Player/Weapon")
	if player == null or weapon == null:
		print("❌ 找不到 Player / Weapon")
		quit()
		return

	# 站定、不散、短射程（见文件头）
	weapon.set("spread_hip", 0.0)
	weapon.set("spread_aim", 0.0)
	weapon.set("range_meters", 6.0)
	weapon.set("tracer_speed", 12.0)   # 放慢，好让弹丸停在画面上
	for _i in 5:
		await process_frame

	var cam := player.get("cam") as Camera3D
	var cam_dir: Vector3 = player.call("camera_forward")
	var origin := cam.global_position
	var muzzle: Vector3 = (weapon.get("muzzle") as Node3D).global_position

	# 开一枪，然后立刻把这次飞行记录读出来（不依赖抓到"正在飞"的那一帧）
	weapon.call("shoot")
	await process_frame
	var rec: Array = []
	if (weapon.get("_in_flight") as Array).size() > 0:
		rec = (weapon.get("_in_flight") as Array)[0]
	var from_new: Vector3 = rec[6] if rec.size() > 6 else muzzle
	var to: Vector3 = rec[2] if rec.size() > 2 else origin + cam_dir * 6.0

	# ── 数值：两条线各偏离准星方向多少度 ──
	var dir_old := (to - muzzle).normalized()
	var dir_new := (to - from_new).normalized()
	var ang_old := rad_to_deg(dir_old.angle_to(cam_dir))
	var ang_new := rad_to_deg(dir_new.angle_to(cam_dir))
	var v := muzzle - origin
	var off_axis := (v - cam_dir * v.dot(cam_dir)).length()
	print("======== 弹道几何 ========")
	print("  枪口离瞄准射线          : %.3f m" % off_axis)
	print("  枪口 → 命中点  偏离准星 : %.2f°   ← 旧路径（拐弯）" % ang_old)
	print("  视觉起点 → 命中点 偏离准星: %.2f°   ← 新路径（应为 0）" % ang_new)
	print("  视觉起点与射线的垂直距离 : %.4f m" % _perp(from_new, origin, cam_dir))
	print("  射击距离                : %.2f m" % origin.distance_to(to))

	# ── 画图：红=旧，绿=新 ──
	_draw_rod(game, muzzle, to, Color(1.0, 0.15, 0.15), 0.05)
	_draw_rod(game, from_new, to, Color(0.15, 1.0, 0.35), 0.05)
	_draw_ball(game, muzzle, Color(1.0, 0.9, 0.1), 0.10)
	_draw_ball(game, from_new, Color(0.2, 1.0, 1.0), 0.10)

	for _i in 8:
		await process_frame
	await _save()

	game.queue_free()
	await process_frame
	quit()


func _perp(p: Vector3, o: Vector3, d: Vector3) -> float:
	var v := p - o
	return (v - d * v.dot(d)).length()


func _draw_rod(parent: Node, a: Vector3, b: Vector3, col: Color, radius: float) -> void:
	var ab := b - a
	var L := ab.length()
	if L < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 1.0
	cm.radial_segments = 8
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var dir := ab.normalized()
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	mi.global_transform = Transform3D(Basis(x, dir, z), a + dir * (L * 0.5))
	mi.scale = Vector3(1.0, L, 1.0)


func _draw_ball(parent: Node, p: Vector3, col: Color, r: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = p


func _save() -> void:
	if DisplayServer.get_name() == "headless":
		print("⚠️ headless 下拿不到渲染纹理，跳过出图")
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_NAME)
	img.save_png(out)
	print("[截图] %s" % out)
