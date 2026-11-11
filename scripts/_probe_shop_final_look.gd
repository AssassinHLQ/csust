extends SceneTree
## 探针：拍**当前真实状态**的白混凝土（不改任何材质，只出图）。
##
## 用途：改完 `shop.gd` 之后验收"跑起来到底长什么样"。
## `_probe_shop_white_concrete.gd` 是四档硬编码覆盖，拍不到真值，所以单独开这个。
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_shop_final_look.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_shop_final/

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_shop_final"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("[焦点自检] %s" % str(OffWin.is_safe()))

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var shop := game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("[错误] 没有 Shop")
		quit(1)
		return
	var sp := shop.global_position
	var tod := get_root().get_node_or_null("TimeOfDay")
	if tod != null:
		tod.call("set_day_minutes", 0.0)

	# 打印真值（不修改）
	var wall: StandardMaterial3D = null
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var ov := (mi as MeshInstance3D).get_surface_override_material(s) as StandardMaterial3D
			if ov == null:
				continue
			var src := m.surface_get_material(s) as StandardMaterial3D
			if src != null and src.resource_name == "PLASTIK_W":
				wall = ov
				break
		if wall != null:
			break
	if wall != null:
		print("墙真值：albedo=%s rough=%.2f metallic=%.2f 贴图=%s normal=%s"
			% [str(wall.albedo_color), wall.roughness, wall.metallic,
				"有" if wall.albedo_texture != null else "无",
				"有" if wall.normal_enabled and wall.normal_texture != null else "无"])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# ── UV 密度 / 法线强度 四档对照（用户 2026-11-11「太粗糙了，不够细腻，近看特别糊」）──
	# 墙网格模型单位 x 跨 168.38 = 实际 8.0 m（缩放 ~21），所以
	#   uv1_scale = N  →  一个贴图周期铺 8/N 米
	# 上一版是 uv1_scale=3 → 周期 2.67 m，一坨斑点 4 m 大，近看必然糊。
	var wall2: StandardMaterial3D = null
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m2 := (mi as MeshInstance3D).mesh
		if m2 == null:
			continue
		for s2 in m2.get_surface_count():
			var ov2 := (mi as MeshInstance3D).get_surface_override_material(s2) as StandardMaterial3D
			if ov2 == null:
				continue
			var src2 := m2.surface_get_material(s2) as StandardMaterial3D
			if src2 != null and src2.resource_name == "PLASTIK_W":
				wall2 = ov2
				break
		if wall2 != null:
			break

	# ⚠️ 近看特写机位：离墙 ~1.2 m，正对墙面（复刻用户那两张图）
	var cam_near := Camera3D.new()
	cam_near.near = 0.05
	cam_near.far = 500.0
	cam_near.fov = 70.0
	root.add_child(cam_near)

	var UV_TIERS := [
		["uv3_old", 3.0, 0.85],     # 上一版：周期 2.67 m
		["uv8", 8.0, 0.55],         # 周期 1.0 m
		["uv16", 16.0, 0.40],       # 周期 0.5 m
		["uv24", 24.0, 0.35],       # 周期 0.33 m
	]

	# 目标墙面：店最里面的那面墙（z 最小），站在它前面 1.2 m
	# 墙面在世界 z ≈ sp.z - 5.4（店进深 10.8，中心在 sp.z）
	var wall_z := sp.z - 5.2
	cam_near.global_position = Vector3(sp.x, 1.55, wall_z + 1.3)
	cam_near.look_at(Vector3(sp.x, 1.55, wall_z), Vector3.UP)

	if wall2 != null and tod != null:
		tod.call("set_hours", 12.0)
		for _f in 60:
			await process_frame
		print("\n── 近看特写：UV 密度 / 法线强度 四档（12:00，镜头离墙 1.3 m）──")
		for t in UV_TIERS:
			var tag2: String = t[0]
			var uv: float = t[1]
			var ns: float = t[2]
			wall2.uv1_scale = Vector3(uv, uv, 1.0)
			wall2.normal_scale = ns
			await _shot(cam_near, out, "zoom_%s" % tag2)
		# 还原成当前真值
		wall2.uv1_scale = Vector3(3.0, 3.0, 1.0)
		wall2.normal_scale = 0.85

	# ① 用户截图那个视角（货架之间，略侧看）
	var cam_user := Camera3D.new()
	cam_user.near = 0.05
	cam_user.far = 500.0
	cam_user.fov = 75.0
	root.add_child(cam_user)
	cam_user.global_position = Vector3(sp.x + 2.2, 1.55, sp.z + 7.0)
	cam_user.look_at(Vector3(sp.x - 0.5, 1.75, sp.z - 4.0), Vector3.UP)

	# ② 店里朝深处
	var cam_in := Camera3D.new()
	cam_in.near = 0.05
	cam_in.far = 500.0
	cam_in.fov = 70.0
	root.add_child(cam_in)
	cam_in.global_position = Vector3(sp.x, 1.62, sp.z + 5.5)
	cam_in.look_at(Vector3(sp.x, 1.35, sp.z - 6.0), Vector3.UP)

	# ③ 店门外往里看
	var cam_door := Camera3D.new()
	cam_door.near = 0.05
	cam_door.far = 500.0
	cam_door.fov = 68.0
	root.add_child(cam_door)
	cam_door.global_position = Vector3(sp.x, 2.4, sp.z - 13.0)
	cam_door.look_at(Vector3(sp.x, 2.2, sp.z), Vector3.UP)

	for h in [12.0, 21.0]:
		if tod != null:
			tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		print("\n── 游戏内 %02d:00 ──" % int(h))
		await _shot(cam_user, out, "%02d_user_view" % int(h))
		await _shot(cam_in, out, "%02d_inside" % int(h))
		await _shot(cam_door, out, "%02d_door" % int(h))

	print("\n[截图] %s" % out)
	quit(0)


func _shot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
	print("   %-16s → %s" % [nm, _stats(img)])


func _stats(img: Image) -> String:
	var a := img.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	var data := a.get_data()
	var n := a.get_width() * a.get_height()
	var blown := 0
	var rs := 0.0
	var gs := 0.0
	var bs := 0.0
	for i in n:
		var o := i * 4
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if r >= 245 and g >= 245 and b >= 245:
			blown += 1
		rs += r
		gs += g
		bs += b
	var fn := float(n)
	return "过曝 %.2f%%｜亮度 %.1f｜暖度 %+.1f" % [
		100.0 * float(blown) / fn,
		(0.2126 * rs + 0.7152 * gs + 0.0722 * bs) / fn,
		(rs - bs) / fn]
