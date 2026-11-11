extends SceneTree
## 探针：**白混凝土**四档对照 —— 用户 2026-11-11「我喜欢白混凝土」。
##
## 背景：上一版按"混凝土物理反照率 0.30~0.50"选了中灰 C (0.48,0.47,0.45)，
## 但实际跑出来偏**暖褐**：因为
##   · `ambient_light_source = 3`（走天空），而天空是**粉紫**的 → 灰墙被染暖
##   · albedo 三通道 (0.48,0.47,0.45) 本身 R>G>B → 又叠一层暖
## 两个暖叠一起 = 生锈墙面，不是"白混凝土"。
##
## 白混凝土该是：**高明度 + 中性偏冷 + 保留粗糙度和颗粒**。
## 反照率抬到 0.58~0.68（白混凝土确实比普通水泥亮），
## 但 roughness 保持 0.85~0.90（哑光）—— 这样既白又不炸。
##
## 四档（都带同一套混凝土贴图）：
##   P1_albedo  (0.68, 0.68, 0.68) neutral  — 纯中性白
##   P2_cool    (0.66, 0.68, 0.70) cool     — 微冷（抵消天空的暖）
##   P3_warm    (0.68, 0.66, 0.63) warm     — 微暖（对照，看是不是你要的）
##   P4_bright  (0.74, 0.75, 0.76) brighter — 更白一档
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_shop_white_concrete.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_shop_white_concrete/

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_shop_white_concrete"

const WALL_MAT := "PLASTIK_W"
const FLOOR_MAT := "Rectangle009__0"

## [标签, albedo_color, roughness]
const TIERS := [
	["C_old_mid", Color(0.48, 0.47, 0.45), 0.90],   # 上一版，作对照
	["P1_neutral", Color(0.68, 0.68, 0.68), 0.88],
	["P2_cool", Color(0.66, 0.68, 0.70), 0.88],
	["P3_warm", Color(0.68, 0.66, 0.63), 0.88],
	["P4_bright_cool", Color(0.75, 0.77, 0.79), 0.86],
]


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

	var wall_mats: Array[StandardMaterial3D] = []
	var floor_mats: Array[StandardMaterial3D] = []
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var ov := (mi as MeshInstance3D).get_surface_override_material(s) as StandardMaterial3D
			if ov == null:
				continue
			var src := m.surface_get_material(s) as StandardMaterial3D
			var nm := src.resource_name if src != null else ""
			if nm == WALL_MAT and not wall_mats.has(ov):
				wall_mats.append(ov)
			elif nm == FLOOR_MAT and not floor_mats.has(ov):
				floor_mats.append(ov)

	print("墙 %d 份、地台 %d 份（贴图：%s）"
		% [wall_mats.size(), floor_mats.size(),
			"有" if not wall_mats.is_empty() and wall_mats[0].albedo_texture != null else "无"])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# 三个机位：朝深处（看整面墙+货架）、朝门口、俯视地面
	var cam_in := Camera3D.new()
	cam_in.near = 0.05
	cam_in.far = 500.0
	cam_in.fov = 70.0
	root.add_child(cam_in)
	cam_in.global_position = Vector3(sp.x, 1.62, sp.z + 5.5)
	cam_in.look_at(Vector3(sp.x, 1.35, sp.z - 6.0), Vector3.UP)

	# 用户截图那个视角：站在货架之间、略微侧看
	var cam_user := Camera3D.new()
	cam_user.near = 0.05
	cam_user.far = 500.0
	cam_user.fov = 75.0
	root.add_child(cam_user)
	cam_user.global_position = Vector3(sp.x + 2.2, 1.55, sp.z + 7.0)
	cam_user.look_at(Vector3(sp.x - 0.5, 1.75, sp.z - 4.0), Vector3.UP)

	for h in [12.0, 21.0]:
		if tod != null:
			tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		print("\n══ 游戏内 %02d:00 ══" % int(h))
		for t in TIERS:
			var tag: String = t[0]
			var col: Color = t[1]
			var rg: float = t[2]
			for m in wall_mats:
				m.albedo_color = col
				m.roughness = rg
			for m in floor_mats:
				m.albedo_color = col
				m.roughness = rg + 0.02
			await _shot(cam_in, out, "%02d_%s_in" % [int(h), tag])
			await _shot(cam_user, out, "%02d_%s_user" % [int(h), tag])

	print("\n[截图] %s" % out)
	quit(0)


func _shot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
	print("   %-20s → %s" % [nm, _stats(img)])


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
	var lum := (0.2126 * rs + 0.7152 * gs + 0.0722 * bs) / fn
	# 暖冷倾向：R-B 为正 = 偏暖，为负 = 偏冷
	var warm := (rs - bs) / fn
	return "过曝 %.2f%%｜亮度 %.1f｜暖度 R-B %+.1f" % [100.0 * float(blown) / fn, lum, warm]
