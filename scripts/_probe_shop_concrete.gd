extends SceneTree
## 探针：把柴关电脑城的**白墙**改成混凝土质感 —— A/B 三档对照。
##
## 用户 2026-11-11：「店里白墙改混凝土的质感，现在是不是反射高了」。
##
## 先回答「反射高」：查了 GLB + `_fix_glb_materials()`，现状是
##     albedo_color = (0.95, 0.96, 0.97)   ← **近乎纯白，反照率 95%**
##     metallic     = 0.0                  ← 镜面反射其实几乎没有
##     roughness    = 0.55                 ← 偏高光
## 所以"反射高"的准确说法是：**反照率过高**（白纸式全反射），不是镜面反射。
## 混凝土的真实反照率大约 0.30~0.45，粗糙度 0.80~0.95，两者都要降。
##
## 出三档 + 现状，同一机位，用数字 + 图一起选：
##   A 现状   (0.95, 0.96, 0.97) rough 0.55
##   B 浅灰混凝土 (0.62, 0.61, 0.59) rough 0.88
##   C 中灰混凝土 (0.48, 0.47, 0.45) rough 0.90
##   D 深灰混凝土 (0.36, 0.355, 0.345) rough 0.92
##
## 机位用 `_probe_shop_inside.gd` 打射线验过的"真在店里"的落点。
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_shop_concrete.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_shop_concrete/{A_now,B_light,C_mid,D_dark}_{in,out}.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_shop_concrete"

## 要改的材质名（GLB 里实际的名字，见文件头表）
const WALL_MAT := "PLASTIK_W"
const FLOOR_MAT := "Rectangle009__0"

## [标签, 墙面 albedo, 墙面 roughness, 地面 albedo, 地面 roughness]
## `FINAL` 这一档 = **直接读脚本真值**（不改材质，看 `_fix_glb_materials()` 的结果）
const TIERS := [
	["A_now", Color(0.95, 0.96, 0.97), 0.55, null, 0.0],
	["B_light", Color(0.62, 0.61, 0.59), 0.88, Color(0.56, 0.55, 0.53), 0.90],
	["C_mid", Color(0.48, 0.47, 0.45), 0.90, Color(0.43, 0.42, 0.40), 0.92],
	["D_dark", Color(0.36, 0.355, 0.345), 0.92, Color(0.32, 0.315, 0.30), 0.94],
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

	# ── 收集被 override 的材质（运行时 `_fix_glb_materials()` 复制出来的那份）──
	var wall_mats: Array[StandardMaterial3D] = []
	var floor_mats: Array[StandardMaterial3D] = []
	var found:= {}
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
				found[WALL_MAT] = true
			elif nm == FLOOR_MAT and not floor_mats.has(ov):
				floor_mats.append(ov)
				found[FLOOR_MAT] = true

	print("\n改到的材质：墙 %d 份、地台 %d 份" % [wall_mats.size(), floor_mats.size()])
	if wall_mats.is_empty():
		print("[错误] 没找到墙材质 %s —— GLB 名字变了？" % WALL_MAT)
		quit(1)
		return
	print("现状：albedo=%s rough=%.2f metallic=%.2f 贴图=%s"
		% [str(wall_mats[0].albedo_color), wall_mats[0].roughness, wall_mats[0].metallic,
			"albedo+rough+normal" if wall_mats[0].albedo_texture != null else "无"])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# 两个机位：朝深处（能看到整面墙）、朝门口
	var cam_in := Camera3D.new()
	cam_in.near = 0.05
	cam_in.far = 500.0
	cam_in.fov = 70.0
	root.add_child(cam_in)
	cam_in.global_position = Vector3(sp.x, 1.62, sp.z + 5.5)
	cam_in.look_at(Vector3(sp.x, 1.35, sp.z - 6.0), Vector3.UP)

	var cam_out := Camera3D.new()
	cam_out.near = 0.05
	cam_out.far = 500.0
	cam_out.fov = 70.0
	root.add_child(cam_out)
	cam_out.global_position = Vector3(sp.x, 1.62, sp.z + 9.5)
	cam_out.look_at(Vector3(sp.x, 1.35, sp.z - 2.0), Vector3.UP)

	for h in [12.0, 21.0]:
		if tod != null:
			tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		print("\n══ 游戏内 %02d:00 ══" % int(h))
		# 先拍「脚本真值」（贴图 + C 档色值，不改任何东西）
		await _shot(cam_in, out, "%02d_FINAL_in" % int(h))
		await _shot(cam_out, out, "%02d_FINAL_out" % int(h))
		for t in TIERS:
			var tag: String = t[0]
			var wc: Color = t[1]
			var wr: float = t[2]
			var fc = t[3]
			var fr: float = t[4]
			for m in wall_mats:
				m.albedo_color = wc
				m.roughness = wr
			if fc != null:
				for m in floor_mats:
					m.albedo_color = fc
					m.roughness = fr
			await _shot(cam_in, out, "%02d_%s_in" % [int(h), tag])
			await _shot(cam_out, out, "%02d_%s_out" % [int(h), tag])

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
	var sum := 0.0
	for i in n:
		var o := i * 4
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if r >= 245 and g >= 245 and b >= 245:
			blown += 1
		sum += 0.2126 * float(r) + 0.7152 * float(g) + 0.0722 * float(b)
	return "过曝 %.2f%%｜平均 %.1f" % [100.0 * float(blown) / float(n), sum / float(n)]
