extends SceneTree
## 探针：柴关电脑城的**营业灯时刻表** —— 20:00 开、06:00 熄。
##
## 用户 2026-11-11：「柴关电脑城晚上才开灯」「要求 20 点到 6 点才开灯」。
##
## 查三样：
##   ① `ShopNightLights.is_on_now()` 的边界（19:59 / 20:00 / 23:59 / 00:00 / 05:59 / 06:00）；
##   ② 真实场景里，把 `TimeOfDay.set_hours()` 拨到几个时刻，读回**每盏灯的实际能量**
##      和招牌/灯管的自发光倍率 —— 不看代码，看运行时真值；
##   ③ 出图：白天全灭 vs 夜里全亮，同一机位对比 + 亮度统计。
##
## 用法（**必须真窗口**才能出图）：
##   & <godot_console.exe> --path . --script res://scripts/_probe_shop_night_lights.gd -- --splat=off --story=off --no-capture
## 出图：_arisu_captures/_shop_night/{12_day,21_night_base,21_night_front,21_night_inside}.png

const OffWin := preload("res://scripts/offscreen_window.gd")
## ⚠️ `--script` 模式下**全局 `class_name` 解析不到**（AGENTS.md 里踩过的同一个坑），
## 必须 preload。下面凡是用到类型的地方都走这两个常量。
const NightLights := preload("res://scripts/shop_night_lights.gd")
const OUT_DIR := "_shop_night"

## 要验的时刻（小时）
const HOURS := [12.0, 19.99, 20.0, 23.5, 0.0, 5.99, 6.0]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("[焦点自检] %s" % str(OffWin.is_safe()))

	# ── ① 纯函数边界（不依赖场景）──
	print("\n① is_on_now() 边界")
	var bad := 0
	for h in HOURS:
		var on: bool = NightLights.is_on_now(float(h))
		var want: bool = float(h) >= 20.0 or float(h) < 6.0
		# 19.99 / 5.99 是边界内的"差一点点"，要对得上 want
		var ok: bool = on == want
		if not ok:
			bad += 1
		print("   %5.2f h → %-5s  期望 %-5s  %s"
			% [h, str(on), str(want), "✓" if ok else "✗"])
	# 跨零点不能写成 `h >= 20 and h < 6`（永远 false），这里把那条也测一下
	if NightLights.is_on_now(23.5) and not NightLights.is_on_now(12.0):
		print("   ✓ 跨零点正确（23.5 开、12 关）")
	else:
		bad += 1
		print("   ✗ 跨零点判断错了")
	print("   边界检查 %s" % ("全过" if bad == 0 else "有 %d 处错" % bad))

	# ── ② 真场景 ──
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
		print("[错误] 场景里没有 Shop")
		quit(1)
		return
	var nl := shop.get_node_or_null("NightLights") as Node
	if nl == null:
		print("[错误] Shop 上没挂 NightLights —— `shop.gd::_wire_baked()` 没接上？")
		quit(1)
		return

	var tod := get_root().get_node_or_null("TimeOfDay")
	if tod == null:
		print("[错误] 没有 TimeOfDay 自动加载")
		quit(1)
		return
	# 时间系统默认 20 分钟一天，会一直走 —— 验的时候让它停住，不然读数会漂
	tod.call("set_day_minutes", 0.0)

	var lights: Array[Light3D] = []
	for n in shop.find_children("*", "OmniLight3D", true, false):
		lights.append(n as Light3D)
	var sign_mat := (shop.get_node_or_null("Body/SignBoard") as MeshInstance3D)
	var sign_sm := sign_mat.material_override as StandardMaterial3D if sign_mat != null else null
	var tubes: Array[StandardMaterial3D] = []
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.emission_enabled and sm.emission.get_luminance() > 0.99 \
						and sm.emission.g >= sm.emission.r:
					tubes.append(sm)

	print("\n② 真场景读数（Shop 世界原点 %s）" % str(shop.global_position.round()))
	print("   接管：%d 盏灯、招牌自发光 %s、灯管 %d 个"
		% [lights.size(), "有" if sign_sm != null else "无", tubes.size()])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = 60.0
	root.add_child(cam)
	# 店门前：站在 Deck 上正对店门（门朝 -Z，店在 z ≈ −15.5）
	var sp := shop.global_position
	cam.global_position = Vector3(sp.x, 2.6, sp.z - 14.0)
	cam.look_at(Vector3(sp.x, 3.0, sp.z), Vector3.UP)

	for h in [12.0, 21.0]:
		tod.call("set_hours", h)
		# 过渡 0.6 s，等够
		for _f in 60:
			await process_frame
		var e: Array[String] = []
		for l in lights:
			e.append("%s=%.2f" % [String(l.name), l.light_energy])
		print("   太阳 %.0f:00 → %s｜招牌自发光 %.2f｜灯管 %.2f"
			% [h, " ".join(e),
				sign_sm.emission_energy_multiplier if sign_sm != null else -1.0,
				tubes[0].emission_energy_multiplier if not tubes.is_empty() else -1.0])
		await _shoot(cam, out, "%02d_%s" % [int(h), "night" if h >= 20.0 or h < 6.0 else "day"])

	# 室内：夜里灯开着的效果（白天那张基本是黑的，也出一张做对照）
	var cam_in := Camera3D.new()
	cam_in.near = 0.05
	cam_in.far = 500.0
	cam_in.fov = 72.0
	root.add_child(cam_in)
	cam_in.global_position = Vector3(sp.x, 1.62, sp.z + 6.0)
	cam_in.look_at(Vector3(sp.x, 1.4, sp.z - 3.0), Vector3.UP)
	for h in [12.0, 21.0]:
		tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		await _shoot(cam_in, out, "%02d_inside" % int(h))

	print("\n[截图] %s" % out)
	quit(0)


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
	print("     %-14s → %s" % [nm, _stats(img)])


func _stats(img: Image) -> String:
	var a := img.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	var data := a.get_data()
	var n := a.get_width() * a.get_height()
	var sum := 0.0
	for i in n:
		var o := i * 4
		sum += 0.2126 * float(data[o]) + 0.7152 * float(data[o + 1]) + 0.0722 * float(data[o + 2])
	return "平均亮度 %.1f/255" % (sum / float(n))
